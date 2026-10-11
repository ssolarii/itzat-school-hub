# Government holiday import

The candidate file contains the 14 observed dates in the Government of Belize's annual 2026 notice, [PR#218-25, issued 6 November 2025](https://www.pressoffice.gov.bz/wp-content/uploads/2025/11/Nov-6-PR218-25-Public-and-Bank-Holidays-2026.pdf). Monday **12 October 2026** is included. Research checked on 10 October 2026 did not locate an official annual 2027 release; the candidate file contains no inferred 2027 dates.

## Import safely

1. Load the latest published document and revision. Preserve existing school calendar entries and all other document fields.
2. For each candidate date, preview a calendar entry with `type:'holiday'`, its official label, and a short description identifying the Government of Belize release. The existing backend calendar schema accepts `type`, `label`, `description`, and optional `bellProfile`; retain detailed source URLs in this companion provenance file or include the source in the description. Do not add unsupported calendar fields to the publish payload.
3. Flag any date already containing a different attendance arrangement for an administrator to review. Do not silently replace an existing asynchronous day or event with scraped data.
4. Review the affected school dates, then publish one atomic revision through the normal publishing API. On a revision conflict, reload and merge before retrying.
5. All imported holidays pause the school's rolling cycle under the user's confirmed policy. Saturday holidays stay visible in the calendar and do not create a second pause or an invented substitute weekday.

This is a reviewed import dataset, not an automatic scraper. Future annual notices and amendments must be checked against the government source, previewed, and imported as new revisions. No dates are automatically shifted from a Saturday, Sunday, or weekday using a guessed rule. School vacations and other closures remain separate entries from the school calendar when supplied.

Do not infer that every future weekday is a confirmed school day merely because its holiday calendar has not yet been published. Keep the source-year coverage explicit in administrative views and documentation.
