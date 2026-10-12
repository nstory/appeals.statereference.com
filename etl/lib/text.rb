#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract the text of each PDF in <download dir>/nnn/ into <text dir>/nnn.txt
# with pdftotext, skipping ones whose text is already there.  Each text is
# written to nnn.txt.part and renamed into place when it's complete, so an
# nnn.txt is always a finished one.  A failed one is left for the next run.
#
# The determinations are Word documents saved as PDF, so they carry their
# text.  One that gives almost none is likely a scan, which would need OCR;
# that's reported as a failure rather than written.

require "fileutils"
require "open3"
require "optparse"

# fewer non-space characters than this and it's probably a scan
MIN_CHARS = 200

def parse_options
  opts = { max: nil, dry_run: false }
  OptionParser.new do |o|
    o.banner = "usage: text.rb --download-dir DIR --text-dir DIR [--max N] [--dry-run]"
    o.on("--download-dir DIR") { |v| opts[:downloads] = v }
    o.on("--text-dir DIR") { |v| opts[:dir] = v }
    o.on("--max N", Integer, "extract at most N files") { |v| opts[:max] = v }
    o.on("--dry-run", "list the DownloadPaths that would be extracted") { opts[:dry_run] = true }
  end.parse!
  abort "--download-dir and --text-dir are required" unless opts[:downloads] && opts[:dir]
  opts
end

# DownloadPaths without text yet, newest first
def plan(downloads, dir)
  paths = Dir.children(downloads).grep(/\A\d+\z/).map { |n| Integer(n) }
  paths.reject { |n| File.exist?(File.join(dir, "#{n}.txt")) }.sort.reverse
end

# the one PDF in <download dir>/nnn/
def pdf(downloads, n)
  files = Dir.children(File.join(downloads, n.to_s))
  raise "expected one file, found #{files.size}" unless files.size == 1

  path = File.join(downloads, n.to_s, files.first)
  raise "#{files.first} isn't a PDF" unless File.binread(path, 5) == "%PDF-"

  path
end

def extract(path)
  text, err, status = Open3.capture3("pdftotext", "-enc", "UTF-8", path, "-")
  raise "pdftotext failed: #{err.strip}" unless status.success?

  text.force_encoding(Encoding::UTF_8)
  chars = text.gsub(/[[:space:]]/, "").size
  raise "only #{chars} characters of text; a scan?" if chars < MIN_CHARS

  text
end

def write_text(dir, n, text)
  path = File.join(dir, "#{n}.txt")
  File.write("#{path}.part", text)
  File.rename("#{path}.part", path)
  path
end

opts = parse_options
FileUtils.mkdir_p(opts[:dir])
todo = plan(opts[:downloads], opts[:dir])
warn "#{todo.size} texts needed"
todo = todo.first(opts[:max]) if opts[:max]

if opts[:dry_run]
  puts todo
  exit
end

failed = 0
todo.each do |n|
  write_text(opts[:dir], n, extract(pdf(opts[:downloads], n)))
rescue StandardError => e
  failed += 1
  warn "#{n}: #{e.message}"
end
warn "#{todo.size - failed} written"
warn "#{failed} failed" if failed.positive?
exit 1 if failed.positive?
