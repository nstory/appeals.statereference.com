#!/usr/bin/env ruby
# frozen_string_literal: true

# Download every Download.aspx?DownloadPath=nnn the searches turned up into
# <download dir>/nnn/<filename the server gives it>, newest (highest nnn)
# first, skipping the ones already there.  Each download is written to
# nnn.part/ and renamed into place when it's complete, so an nnn/ directory
# is always a finished download.  A failed one is left for the next run.
#
# curl gets Imperva's security check after a handful of requests, so we fetch
# from inside a Chrome window instead; see appeals_web.rb.

require "base64"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "tempfile"
require "uri"
require_relative "appeals_web"

DOWNLOAD_URL = "https://www.sec.state.ma.us/AppealsWeb/Download.aspx?DownloadPath="

def parse_options
  opts = { max: nil, dry_run: false, delay: 1.0 }
  OptionParser.new do |o|
    o.banner = "usage: downloads.rb --search-dir DIR --download-dir DIR --profile-dir DIR " \
               "[--max N] [--delay SECONDS] [--dry-run]"
    o.on("--search-dir DIR") { |v| opts[:searches] = v }
    o.on("--download-dir DIR") { |v| opts[:dir] = v }
    o.on("--profile-dir DIR", "Chrome profile") { |v| opts[:profile] = v }
    o.on("--max N", Integer, "download at most N files") { |v| opts[:max] = v }
    o.on("--delay SECONDS", Float, "pause between downloads (default 1)") { |v| opts[:delay] = v }
    o.on("--dry-run", "list the DownloadPaths that would be fetched") { opts[:dry_run] = true }
  end.parse!
  abort "--search-dir, --download-dir and --profile-dir are required" unless opts[:searches] && opts[:dir] && opts[:profile]
  opts
end

# DownloadPaths in the searches that aren't downloaded yet, newest first
def plan(searches, dir)
  paths = Dir.glob(File.join(searches, "*.json")).flat_map do |file|
    JSON.parse(File.read(file))["rows"].flat_map { |row| row["download_paths"] }
  end
  paths.uniq.reject { |n| File.directory?(File.join(dir, n.to_s)) }.sort.reverse
end

class Downloader < AppealsWeb
  # [filename, content] of DownloadPath n
  def download(n)
    past_check { download_once(n) }
  end

  private

  def download_once(n)
    # the fetch has to come from a page on the site to carry its cookies
    @page.go_to(URL) unless @page.url.to_s.start_with?(URL[%r{\Ahttps://[^/]+/}])
    res = @page.evaluate_async(<<~JS, 120, "#{DOWNLOAD_URL}#{n}")
      const [url, done] = arguments;
      fetch(url).then(async r => {
        const blob = await r.blob();
        const reader = new FileReader();
        reader.onload = () => done({
          status: r.status,
          type: r.headers.get("content-type"),
          disposition: r.headers.get("content-disposition"),
          data: reader.result.slice(reader.result.indexOf(",") + 1)
        });
        reader.readAsDataURL(blob);
      }).catch(e => done({ error: String(e) }));
    JS
    if res["error"]
      # Chrome fails a download whose unquoted filename has commas in it
      # ("spr243258, spr243261.pdf") as having several Content-Dispositions,
      # so fetch those with curl and Chrome's cookies instead
      res = curl("#{DOWNLOAD_URL}#{n}")
    else
      res["body"] = Base64.decode64(res["data"])
    end

    body = res["body"]
    disposition = res["disposition"].to_s
    unless res["status"] == 200 && disposition.match?(/attachment/i)
      raise Blocked if body.include?("_Incapsula_Resource")

      raise "not a download: HTTP #{res["status"]} #{res["type"]} #{body.bytesize} bytes"
    end
    [filename(disposition, n), body]
  end

  # what download_once wants to know of a GET of url, made with curl as Chrome
  def curl(url)
    cookies = @page.cookies.all.values.map { |c| "#{c.name}=#{c.value}" }.join("; ")
    agent = @page.evaluate("navigator.userAgent")
    Tempfile.create("headers") do |headers|
      body, err, status = Open3.capture3("curl", "--silent", "--show-error", "--max-time", "120",
                                         "--dump-header", headers.path, "--user-agent", agent,
                                         "--header", "Cookie: #{cookies}", url, binmode: true)
      raise "curl failed: #{err.strip}" unless status.success?

      # the last response's headers, should curl report more than one
      lines = File.read(headers.path).split(/\r?\n\r?\n/).reject(&:empty?).last.to_s.lines
      fields = lines.drop(1).to_h { |l| l.split(":", 2).map(&:strip) }.transform_keys(&:downcase)
      { "status" => lines.first.to_s[/\AHTTP\/\S+ (\d+)/, 1].to_i, "type" => fields["content-type"],
        "disposition" => fields["content-disposition"], "body" => body }
    end
  end

  # "attachment;filename=spr264043.pdf" => "spr264043.pdf"
  def filename(disposition, n)
    name = disposition[/filename\*?=(?:UTF-8'')?"?([^";]+)"?/i, 1].to_s
    name = URI.decode_www_form_component(name) if disposition.match?(/filename\*=/i)
    name = name.tr("/\\\0", "_").strip
    name.empty? || name.start_with?(".") ? "#{n}.pdf" : name
  end
end

def write_download(dir, n, name, body)
  final = File.join(dir, n.to_s)
  part = "#{final}.part"
  FileUtils.rm_rf(part)
  FileUtils.mkdir_p(part)
  File.binwrite(File.join(part, name), body)
  File.rename(part, final)
  File.join(n.to_s, name)
end

opts = parse_options
FileUtils.mkdir_p(opts[:dir])
todo = plan(opts[:searches], opts[:dir])
warn "#{todo.size} downloads needed"
todo = todo.first(opts[:max]) if opts[:max]

if opts[:dry_run]
  puts todo
  exit
end

site = Downloader.new(opts[:profile])
failed = 0
begin
  todo.each_with_index do |n, i|
    sleep opts[:delay] if i.positive?
    name, body = site.download(n)
    warn "#{write_download(opts[:dir], n, name, body)}: #{body.bytesize} bytes"
  rescue Ferrum::Error => e
    failed += 1
    warn "#{n}: #{e.class}: #{e.message}"
    # start over with a fresh browser in case it's the one that's broken
    site.quit rescue nil
    site = Downloader.new(opts[:profile])
  rescue StandardError => e
    failed += 1
    warn "#{n}: #{e.class}: #{e.message}"
  end
ensure
  site.quit
end
warn "#{failed} failed" if failed.positive?
exit 1 if failed.positive?
