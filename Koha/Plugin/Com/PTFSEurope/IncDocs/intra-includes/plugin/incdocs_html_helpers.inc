[% USE raw %]

[% BLOCK inc_docs_header %]
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
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3APTFSEurope%3A%3AIncDocs&amp;method=configure">IncDocs</a>
            [% END %]
            [% FOREACH incdocs_bc_item IN incdocs_bc_items %]
                [% WRAPPER breadcrumb_item bc_active = incdocs_bc_item.active %]
                    <a href="[% incdocs_bc_item.url %]">[% incdocs_bc_item.name %]</a>
                [% END %]
            [% END %]
        [% END #/ WRAPPER breadcrumbs %]
    [% END #/ WRAPPER sub-header.inc %]
[% END %]

[% BLOCK inc_docs_sidebar %]
    <div class="col-md-2 order-sm-2 order-md-1">
        <aside>
            <div id="menu">
            <h5>IncDocs</h5>
                <ul>
                <li class="[% page == 'configuration' ? 'active' : '' %]">
                
                    <a title="Configuration" href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3APTFSEurope%3A%3AIncDocs&amp;method=configure"><i class="fa fa-gear"></i> Configuration</a>
                </li>
                <li class="[% page == 'libraries' ? 'active' : '' %]">
                    <a title="Libraries" href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3APTFSEurope%3A%3AIncDocs&amp;method=tool"><i class="fa fa-list"></i> Libraries</a>
                </li>
                </ul>
            </div>
        </aside>
    </div>
[% END %]