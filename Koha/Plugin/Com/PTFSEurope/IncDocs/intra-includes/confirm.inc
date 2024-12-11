[% USE Koha %]
[% incdocsRsp = whole.backend_availability.response.data %]
<div class="page-section">
    [% IF whole.stage == "availability" %]
        <table border="1" cellpadding="5" cellspacing="0">
        [% IF whole.backend_availability.error %]
            <h3 class="text-danger">[% whole.backend_availability.error %]</h2>
            <a href="/cgi-bin/koha/ill/ill-requests.pl?op=illview&amp;illrequest_id=14">Return to request</a>
        [% END %]
        [% IF whole.backend_availability.success %]
            <h3 class="text-success">This item is available</h2>
            <button class="btn btn-primary">Place request with IncDocs</button>
        [% END %]
        [% IF incdocsRsp %]
            <h3>IncDocs response details:</h2>
            [% FOREACH item IN incdocsRsp %]
                <tr>
                <td style="padding: 5px">[% item.key %]</td>
                <td style="padding: 5px">
                [% IF item.value.size > 1 %]
                    [% FOREACH subitem IN item.value %]
                        <strong>[% subitem.key %]</strong> : [% subitem.value %]<br>
                    [% END %]
                [% ELSE %]
                    [% item.value %]
                [% END %]
                </tr>
            [% END %]
        [% END %]
        </table>
    [% END %]
</div>