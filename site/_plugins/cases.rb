require "json"
require "set"

# Counts the lines of etl/output/cases.jsonl for the homepage to report, in
# site.data.case_count, along with the oldest and newest dates among them in
# site.data.oldest_date and site.data.newest_date.  The case types, commonest
# first, are left in site.data.types and the years the cases are dated, newest
# first, in site.data.years, for the search page's filters; a case's date and
# year are as lib/search_index.mjs indexes them.  The cases have no pages of
# their own; search results link to AppealsWeb (see lib/search_index.mjs).
module Cases
  class Generator < Jekyll::Generator
    safe true

    def generate(site)
      path = File.expand_path("../etl/output/cases.jsonl", site.source)
      count = 0
      types = Hash.new(0)
      years = Set.new
      dates = []
      File.foreach(path) do |line|
        appeal = JSON.parse(line)
        count += 1
        types[appeal["type"]] += 1
        date = appeal["closed"] || appeal["opened"]
        next unless date
        years << date[0, 4]
        dates << date
      end
      site.data["case_count"] = count
      site.data["types"] = types.sort_by { |_, n| -n }.map(&:first)
      site.data["years"] = years.sort.reverse
      site.data["oldest_date"], site.data["newest_date"] = dates.minmax
    end
  end
end
