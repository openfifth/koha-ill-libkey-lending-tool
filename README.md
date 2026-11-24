# Koha ILL Incdocs Lending Tool backend

This backend provides the ability to create Interlibrary Loan requests using the LibKey Lending Tool API service.

![workflow diagram](https://github.com/PTFS-Europe/koha-ill-libkey-lending-tool/blob/main/incdocs_workflow.png?raw=true)

This plugin is designed to only work with AutoILLBackendPriority.

## System preferences

### ILLModuleUnmediated

This backend utilizes the ILLModuleUnmediated system preference.
If enabled, requests are placed as soon as they're created and are set to "Requested" status.
Otherwise, requests are created with the "New" status and manual confirmation to place the request is required.
This is only true for Staff created requests. Requests created from the OPAC always require mediation.

### IllLog

This backend utilizes the IllLog system preference.
If enabled, IncDocs transactions are stored in the ILL request log for review.

## Requirements

From version 3.0.0, this plugin requires Koha 26.11 with [bug 41091](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41091).
Requests found at another library are sent over ISO18626 to the supplying agency set for that library on the 'IncDocs libraries' page.

## Receiving documents

When the supplying agency sends the article, the request goes to 'Copy completed'. Then:

1) 'Retrieve document' downloads the article into the request's documents, tells the supplying agency it was received, and sets the request to 'Document received'
2) 'Send to patron' sends the patron the 'ILL document ready for download' (ILL_DOCUMENT_READY) notice and completes the request

The patron needs an email address and the 'Interlibrary loan ready' messaging preference for the notice.
On Koha versions without `Koha::ILL::ISO18626::Requester->retrieve_document`, 'Copy completed' completes the request instead, with the article link as its access URL.

## Upgrading to 3.0.0

Version 3.0.0 no longer places requests with ThirdIron or checks their status, so the IncDocs status cron and the cancellation email are gone. Requests already placed with ThirdIron must be finished before upgrading.

1) Set up a supplying agency for each lending library in 'Interlibrary loans > Supplying agencies'
2) Stop placing requests found at another library
3) Wait until this report returns no rows (IncDocs requests placed with ThirdIron that are still 'Requested'):

```sql
SELECT illrequest_id
FROM illrequests
WHERE backend = 'IncDocs'
AND status = 'REQ'
AND illrequest_id NOT IN (
    SELECT illrequest_id FROM illrequestattributes WHERE type = 'iso18626_supplying_agency_id'
)
```

4) Upgrade Koha and the plugin, then set the supplying agency for each lending library on the 'IncDocs libraries' page
5) Remove the `process_incdocs_updates.pl` cron job

If any of these requests are left, the upgrade logs their IDs so they can be followed up with the lending library.

## Libkey Lending Tool Documentation

* [https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation](https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation).

## Email template notice example for 'found locally' articles.
This is used to send an email to the patron with the link to the article.
See [notice.example](Koha/Plugin/Com/PTFSEurope/IncDocs/docs/notice.example).
This template notice must be created as an HTML message.

## Batch article URLs report

To enable the "Print article URLs for this batch" button on the batch request list page, create a saved SQL report in Koha with the following query and enter its report ID in the plugin configuration under **Batches options > Article URLs report ID**.

The report takes a batch ID as its parameter and lists all requests in that batch that have a locally available article URL (i.e. requests completed via the 'found locally' path).

```sql
SELECT
    ir.illrequest_id       AS "Request ID",
    CONCAT(b.firstname, ' ', b.surname) AS "Patron",
    b.email                AS "Patron email",
    COALESCE(atitle.value, title.value) AS "Title",
    author.value           AS "Author",
    CONCAT('<a href=\"', ir.accessurl,'\">', ir.accessurl, '</a>') AS "Content URL"
FROM illrequests ir
LEFT JOIN borrowers b ON b.borrowernumber = ir.borrowernumber
LEFT JOIN illrequestattributes atitle
    ON atitle.illrequest_id = ir.illrequest_id AND atitle.type = 'article_title'
LEFT JOIN illrequestattributes title
    ON title.illrequest_id = ir.illrequest_id AND title.type = 'title'
LEFT JOIN illrequestattributes author
    ON author.illrequest_id = ir.illrequest_id AND author.type = 'article_author'
WHERE ir.batch_id = <<Batch ID>>
AND ir.accessurl IS NOT NULL AND ir.accessurl != ''
ORDER BY ir.illrequest_id
```
