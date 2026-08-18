# Koha ILL Incdocs Lending Tool backend

This backend provides the ability to create Interlibrary Loan requests using the LibKey Lending Tool API service.

![workflow diagram](https://github.com/PTFS-Europe/koha-ill-libkey-lending-tool/blob/main/incdocs_workflow.png?raw=true)

This plugin is designed to only work with AutoILLBackendPriority.

## System preferences

### ILLModuleUnmediated

This backend utilizes the ILLModuleUnmediated system preference.
If enabled, requests are placed with IncDocs as soon as they're created and are set to "Requested" status.
Otherwise, requests are created with the "New" status and manual confirmation to place the request with IncDocs is required.
This is only true for Staff created requests. Requests created from the OPAC always require mediation.

### IllLog

This backend utilizes the IllLog system preference.
If enabled, IncDocs transactions are stored in the ILL request log for review.

## Requirements

Only compatible with Koha 25.05+

This plugin requires [bug 38663](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=38663)

## Libkey Lending Tool Documentation

* [https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation](https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation).

## IncDocs status update cron example (update every 30 minutes)
See [crontab.example](Koha/Plugin/Com/PTFSEurope/IncDocs/cron/crontab.example) for a working example in k-t-d (needs adjusting for a live environment)

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
