#!/usr/bin/env ruby
# frozen_string_literal: true

# Search AppealsWeb by closed date and save each search to
# <search dir>/YYYYMMDD_X_YYYYMMDD_YYYYMMDD.json (see README.md), working out
# from the files already there which days still need searching.
#
# A search run on day D can't have seen cases closed later on D, so a file
# covers its date range only up to the day before it was run.  Every day from
# FLOOR through today that no file covers is searched, per date type, in
# chunks of up to CHUNK days, newest first.  Run daily, that's one search per
# type over yesterday and today; on an empty directory it's the full backfill.
#
# Each row's determination PDFs are postback buttons that redirect to
# Download.aspx?DownloadPath=nnn, and they only work from the page that ran
# the search, so we resolve them here, before moving on.  A search is written
# only once every PDF is resolved; a failed one leaves its days uncovered for
# the next run.
#
# The site is behind Imperva, which turns away plain HTTP posts and headless
# Chrome, and now and then wants a human to pass a security check.  So we
# drive a Chrome window, and when the check comes up we wait for you to click
# through it there, then start that search over.  Chrome keeps its profile in
# --profile-dir, so the cookie from passing the check outlives the run.

require "date"
require "fileutils"
require "ferrum"
require "json"
require "nokogiri"
require "optparse"
require "set"
require "time"
require "uri"

URL = "https://www.sec.state.ma.us/AppealsWeb/AppealsStatus.aspx"

# letter in the filename => ddlDateType value
DATE_TYPES = {
  "I" => "1", # Initial closed
  "R" => "5", # Reconsideration closed
  "C" => "7"  # In camera review closed
}.freeze

# earliest year in the form's case year dropdown
FLOOR = Date.new(2014, 1, 1)
CHUNK = 2
FILENAME = /\A(\d{8})_([#{DATE_TYPES.keys.join}])_(\d{8})_(\d{8})\.json\z/

COLUMNS = %w[case_no opened extended_deadline closed type sub_type status requester custodian].freeze
# extended_deadline isn't a date: it's "Yes" or empty
DATE_COLUMNS = %w[opened closed].freeze

def parse_options
  opts = { max: nil, dry_run: false, today: Date.today }
  OptionParser.new do |o|
    o.banner = "usage: searches.rb --search-dir DIR --profile-dir DIR [--max N] [--dry-run]"
    o.on("--search-dir DIR") { |v| opts[:dir] = v }
    o.on("--profile-dir DIR", "Chrome profile") { |v| opts[:profile] = v }
    o.on("--max N", Integer, "run at most N searches") { |v| opts[:max] = v }
    o.on("--dry-run", "list the searches that would run") { opts[:dry_run] = true }
  end.parse!
  abort "--search-dir and --profile-dir are required" unless opts[:dir] && opts[:profile]
  opts
end

def ymd(date) = date.strftime("%Y%m%d")

# date type letter => Set of days the existing files cover
def covered_days(dir)
  covered = Hash.new { |h, k| h[k] = Set.new }
  Dir.children(dir).each do |name|
    next unless (m = name.match(FILENAME))

    searched, type, from, to = m.captures
    last = [Date.parse(to), Date.parse(searched) - 1].min
    (Date.parse(from)..last).each { |d| covered[type] << d }
  end
  covered
end

# [type, from, to] for every search still needed, newest first
def plan(dir, today)
  covered = covered_days(dir)
  chunks = DATE_TYPES.keys.flat_map do |type|
    days = today.downto(FLOOR).reject { |d| covered[type].include?(d) }
    # runs of consecutive days, newest first, cut into chunks of CHUNK days
    days.slice_when { |a, b| a - b != 1 }
        .flat_map { |run| run.each_slice(CHUNK).map { |c| [type, c.last, c.first] } }
  end
  chunks.sort_by.with_index { |(_, _, to), i| [-to.jd, i] }
end

# Imperva put up its security check, or answered a post with it
class Blocked < StandardError; end

class AppealsWeb
  # searches that run into the security check this many times give up
  ATTEMPTS = 3

  def initialize(profile)
    @browser = Ferrum::Browser.new(headless: false, timeout: 60,
                                   browser_options: { "user-data-dir" => File.expand_path(profile) })
    @page = @browser.create_page
  end

  def quit = @browser.quit

  # rows closed between from and to, with each row's DownloadPaths.  A
  # search the security check interrupts starts over once it's passed, since
  # we can't tell where passing it leaves the page.
  def search(type, from, to)
    attempt = 0
    begin
      attempt += 1
      search_once(type, from, to)
    rescue Blocked
      raise "still running into the security check after #{ATTEMPTS} tries" if attempt >= ATTEMPTS

      pass_check
      retry
    end
  end

  private

  def search_once(type, from, to)
    @page.go_to(URL)
    wait_for { form? }
    # choosing a date type posts back to enable the date fields
    postback(<<~JS)
      document.getElementById("ddlDateType").value = #{DATE_TYPES.fetch(type).to_json};
      __doPostBack("ddlDateType", "");
    JS
    postback(<<~JS)
      document.getElementById("txtDateFrom").value = #{from.strftime("%m/%d/%Y").to_json};
      document.getElementById("txtDateTo").value = #{to.strftime("%m/%d/%Y").to_json};
      document.getElementById("ddlPerPage").value = "30000";
      document.getElementById("BtnSearchAppeal").click();
    JS
    rows(Nokogiri::HTML(@page.body))
  end

  # Wait, as long as it takes, for you to pass the security check in the
  # Chrome window.  A post that got the check doesn't show it, so we load the
  # search page to bring it up.
  def pass_check
    @page.go_to(URL)
    return unless blocked?

    warn "\aImperva wants a security check: click through it in the Chrome window"
    sleep 1 until form_loaded?
    warn "security check passed"
  end

  def form_loaded?
    form?
  rescue Ferrum::Error
    false
  end

  def form? = @page.evaluate(%(!!document.getElementById("ddlDateType")))

  def blocked? = @page.evaluate(%(!!document.querySelector("iframe[src*='_Incapsula_Resource']")))

  # Run js, which submits the form, and wait for the page it loads.  The
  # marker on window goes away with the old page, so we can't mistake the
  # old page for the new one.
  def postback(js)
    @page.execute("window.__searching = true; #{js}")
    wait_for do
      @page.evaluate(%(window.__searching === undefined && document.readyState === "complete")) && form?
    end
  end

  def wait_for(timeout: 300)
    deadline = Time.now + timeout
    loop do
      begin
        return if yield
        raise Blocked if blocked?
      rescue Ferrum::Error
        # the page went away mid-check; try again
      end
      raise "timed out waiting for AppealsWeb" if Time.now > deadline

      sleep 0.25
    end
  end

  def rows(doc)
    grid = doc.at_css("#GrdWebStatusReport")
    return [] unless grid

    grid.css("tr").filter_map do |tr|
      cells = tr.css("> td")
      next unless cells.size > COLUMNS.size

      row = COLUMNS.zip(cells).to_h { |col, td| [col, td.text.gsub(/[[:space:]]+/, " ").strip] }
      DATE_COLUMNS.each do |col|
        row[col] = iso(row[col])
      rescue Date::Error
        raise "case #{row["case_no"]}: can't read #{col} #{row[col].inspect}"
      end
      row.transform_values! { |v| v == "" ? nil : v }
      row["detail_token"] = detail_token(cells[0])
      row["download_paths"] = cells[COLUMNS.size].css("input[type=image]").map { |i| download_path(i["name"]) }
      row
    end
  end

  # "09-30-2026" => "2026-09-30"
  def iso(text)
    return text if text.empty?

    Date.strptime(text, "%m-%d-%Y").iso8601
  end

  def detail_token(cell)
    href = cell.at_css("a[href*='AppealStatusDetail']")&.[]("href")
    href && URI.decode_www_form(URI(href).query).to_h["AppealNo"]
  end

  # Post the form as a click on PDF button <name> would, and read the
  # DownloadPath off the URL the post redirects to.  fetch rather than a
  # click keeps the results page where it is for the next button.
  def download_path(name)
    url = @page.evaluate_async(<<~JS, 120, name)
      const [name, done] = arguments;
      const form = document.getElementById("__VIEWSTATE").form;
      const body = new URLSearchParams(new FormData(form));
      body.set(name + ".x", "8");
      body.set(name + ".y", "8");
      const abort = new AbortController();
      fetch(form.action, { method: "POST", body, signal: abort.signal })
        .then(r => {
          if (r.url.includes("Download.aspx")) { done(r.url); abort.abort(); }
          else r.text().then(t => done(t.includes("_Incapsula_Resource") ? "blocked" : r.url));
        })
        .catch(e => done("error: " + e));
    JS
    raise Blocked if url == "blocked"

    path = url.start_with?("http") && URI.decode_www_form(URI(url).query || "").to_h["DownloadPath"]
    raise "#{name} didn't lead to a download: #{url}" unless path&.match?(/\A\d+\z/)

    Integer(path)
  end
end

def write_search(dir, type, from, to, rows, searched_at)
  name = "#{ymd(searched_at.to_date)}_#{type}_#{ymd(from)}_#{ymd(to)}.json"
  path = File.join(dir, name)
  json = JSON.pretty_generate(
    "searched_at" => searched_at.iso8601,
    "date_type" => type,
    "from" => from.iso8601,
    "to" => to.iso8601,
    "rows" => rows
  )
  File.write("#{path}.part", "#{json}\n")
  File.rename("#{path}.part", path)
  name
end

opts = parse_options
FileUtils.mkdir_p(opts[:dir])
todo = plan(opts[:dir], opts[:today])
warn "#{todo.size} searches needed"
todo = todo.first(opts[:max]) if opts[:max]

if opts[:dry_run]
  todo.each { |type, from, to| puts "#{type} #{from} #{to}" }
  exit
end

site = AppealsWeb.new(opts[:profile])
failed = 0
begin
  todo.each do |type, from, to|
    searched_at = Time.now
    rows = site.search(type, from, to)
    name = write_search(opts[:dir], type, from, to, rows, searched_at)
    pdfs = rows.sum { |r| r["download_paths"].size }
    warn "#{name}: #{rows.size} rows, #{pdfs} pdfs (#{(Time.now - searched_at).round}s)"
  rescue Ferrum::Error => e
    failed += 1
    warn "#{type} #{from} #{to}: #{e.class}: #{e.message}"
    # start over with a fresh browser in case it's the one that's broken
    site.quit rescue nil
    site = AppealsWeb.new(opts[:profile])
  rescue StandardError => e
    failed += 1
    warn "#{type} #{from} #{to}: #{e.class}: #{e.message}"
  end
ensure
  site.quit
end
exit 1 if failed.positive?
