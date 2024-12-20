# Koha Interlibrary Loans Incdocs Lending Tool backend

This backend provides the ability to create Interlibrary Loan requests using the LibKey Lending Tool API service.

## ILLModuleUnmediated

This backend utilizes the ILLModuleUnmediated system preference.
If enabled, requests are placed with IncDocs as soon as they're created and are set to "Requested" status.
Otherwise, requests are created with the "New" status and manual confirmation to place the request with IncDocs is required.

## Requirements

Only compatible with Koha 25.05+

This plugin requires [bug 38663](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=38663)

## Documentation

* [https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation](https://thirdiron.atlassian.net/wiki/spaces/BrowZineAPIDocs/pages/3550019585/LibKey+Lending+Tool+API+Documentation).
