[% USE raw %]

[% INCLUDE 'doc-head-open.inc' %]
 <title>Koha: IncDocs</title>
[% INCLUDE 'doc-head-close.inc' %]
</head>

<body>
[% WRAPPER 'header.inc' %]
    [% INCLUDE 'cat-search.inc' %]
[% END %]

[% WRAPPER 'sub-header.inc' %]
    [% WRAPPER breadcrumbs %]
        [% WRAPPER breadcrumb_item %]
            <a href="/cgi-bin/koha/plugins/plugins-home.pl">Plugins</a>
        [% END %]
    [% END #/ WRAPPER breadcrumbs %]
[% END #/ WRAPPER sub-header.inc %]