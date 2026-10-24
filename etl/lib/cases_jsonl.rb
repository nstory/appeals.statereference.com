#!/usr/bin/env ruby
# frozen_string_literal: true

# Build <output>, cases.jsonl: one line per case in the searches, with the
# case's row from the search results, a link to its detail page and links to
# its PDFs, and the text of all its PDFs in `fulltext`, for search.
#
# A case closed more than once (initially, then on reconsideration or in
# camera review) turns up in more than one search, so we take its row from the
# search run most recently.
#
# Each PDF links to AppealsWeb's Download.aspx and to our copy in R2 (see
# r2-sync in the Makefile), with the filename the server gave the download.
# The filename and R2 link are null when we haven't downloaded it.  A PDF
# whose text we don't have yet (see text.rb) is left out of the fulltext.

require "fileutils"
require "json"
require "optparse"
require "uri"

DETAIL_URL = "https://www.sec.state.ma.us/AppealsWeb/AppealStatusDetail.aspx?AppealNo="
DOWNLOAD_URL = "https://www.sec.state.ma.us/AppealsWeb/Download.aspx?DownloadPath="

FIELDS = %w[case_no opened extended_deadline closed type sub_type status requester custodian].freeze

def parse_options
  opts = {}
  OptionParser.new do |o|
    o.banner = "usage: cases_jsonl.rb --search-dir DIR --download-dir DIR --text-dir DIR --r2-url URL --output FILE"
    o.on("--search-dir DIR") { |v| opts[:searches] = v }
    o.on("--download-dir DIR") { |v| opts[:downloads] = v }
    o.on("--text-dir DIR") { |v| opts[:texts] = v }
    o.on("--r2-url URL") { |v| opts[:r2_url] = v.chomp("/") }
    o.on("--output FILE") { |v| opts[:output] = v }
  end.parse!
  unless opts[:searches] && opts[:downloads] && opts[:texts] && opts[:r2_url] && opts[:output]
    abort "--search-dir, --download-dir, --text-dir, --r2-url and --output are required"
  end
  opts
end

# case_no => its row from the search run most recently
def latest_rows(searches)
  searches = Dir.glob(File.join(searches, "*.json")).map { |f| JSON.parse(File.read(f)) }
  searches.sort_by { |s| s["searched_at"] }.each_with_object({}) do |search, rows|
    search["rows"].each { |row| rows[row["case_no"]] = row }
  end
end

# the name of the one file in <download dir>/nnn/, or nil if it isn't downloaded
def download_filename(downloads, n)
  dir = File.join(downloads, n.to_s)
  File.directory?(dir) ? Dir.children(dir).first : nil
end

# the texts of the PDFs we have text for, one after another
def fulltext(texts, paths)
  paths.filter_map do |n|
    path = File.join(texts, "#{n}.txt")
    File.read(path, encoding: Encoding::UTF_8).tr("\f", "\n").strip if File.exist?(path)
  end.join("\n\n")
end

# input/downloads/nnn/xxx.pdf is synced to appeals/nnn/xxx.pdf in R2
def r2_url(r2_url, n, filename)
  filename && "#{r2_url}/#{n}/#{URI.encode_uri_component(filename)}"
end

def case_line(row, downloads, texts, r2)
  JSON.generate(
    **row.slice(*FIELDS),
    detail_url: DETAIL_URL + URI.encode_www_form_component(row["detail_token"]),
    pdfs: row["download_paths"].map do |n|
      filename = download_filename(downloads, n)
      { download_path: n, url: "#{DOWNLOAD_URL}#{n}", filename:, r2_url: r2_url(r2, n, filename) }
    end,
    fulltext: fulltext(texts, row["download_paths"])
  )
end

opts = parse_options
rows = latest_rows(opts[:searches])
lines = rows.keys.sort.reverse.map { |case_no| case_line(rows[case_no], opts[:downloads], opts[:texts], opts[:r2_url]) }

FileUtils.mkdir_p(File.dirname(opts[:output]))
File.open("#{opts[:output]}.part", "w") { |f| f.puts(lines) }
File.rename("#{opts[:output]}.part", opts[:output])

missing = rows.values.sum { |row| row["download_paths"].count { |n| !File.directory?(File.join(opts[:downloads], n.to_s)) } }
warn "#{lines.size} cases written to #{opts[:output]}"
warn "#{missing} PDFs not downloaded yet" if missing.positive?
untexted = rows.values.sum { |row| row["download_paths"].count { |n| !File.exist?(File.join(opts[:texts], "#{n}.txt")) } }
warn "#{untexted} PDFs without text yet" if untexted.positive?
