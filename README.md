# appeals.statereference.com
Database of determinations made by the Massachusetts Supervisor of Records.

[Visit the site](https://appeals.statereference.com)

## AI Policy
Almost all of the code in this repo was written by [Claude Code](https://claude.com/product/claude-code). Two principles:
- AI is for writing code that's run by the computer
- AI is not for writing English that's read by humans

## FILES & DIRECTORIES
| path | purpose |
|--------|-------|
| etl | scripts to download and parse appeals |
| etl/input/searches/ | JSON file for each search performed |
| etl/input/downloads/nnn/ | contains file from Download.aspx?DownloadPath=nnn |
| etl/input/text/nnn.txt | text extracted from the pdf in downloads/nnn |
| etl/output/cases.jsonl | one row per case with metadata and links to PDFs |
| site | jekyll site for appeals.statereference.com |

## SEARCHES
Searches are against [AppealsWeb](https://www.sec.state.ma.us/AppealsWeb/AppealsStatus.aspx). Each search is stored in a file: `YYYYMMDD_X_YYYYMMDD_YYYMMDD.json`
- 1st date is when search was performed
- 2nd date is start date
- 3nd date is end date
- X=I for Date type "Initial closed"
- X=R for Date type "Reconsideration closed"
- X=C for Date type "In camera review closed"

## TODO
- [X] mirror PDFs to R2 (no way to hotlink b/c content-disposition: attachment)
- [ ] add example searches
