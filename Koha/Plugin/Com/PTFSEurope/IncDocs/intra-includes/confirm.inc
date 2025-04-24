[% USE Koha %]
[% incdocsRsp = whole.backend_availability.response.data %]
<div class="page-section">
    [% IF whole.stage == "availability" %]
        <div class="rows">
            <table border="1" cellpadding="5" cellspacing="0">
            <ol>
            [% IF whole.backend_availability.error %]
                <h3 class="text-danger">[% whole.backend_availability.error %]</h2>
            [% END %]
            [% IF whole.backend_availability.success.defined %]
                <h3 class="text-success">
                    This item is available
                    [% IF whole.fresh_library %] at a different library [% END %]
                </h3>
                <h3 class="text-success">[% whole.backend_availability.success %]</h2>
                    [% SET get_params = "op=" _ whole.method _ "&stage=" _ whole.future _ "&illrequest_id=" _ whole.illrequest_id %]
                    [% FOREACH key IN incdocsRsp.keys %]
                        [% value = incdocsRsp.$key %]
                        [% IF key != 'op' && key != 'method' && key != 'custom_key' && key != 'custom_value' && key != 'csrf_token' %]
                            [% value = value | uri %]
                            [% get_params = get_params _ "&" _ key _ "=" _ value %]
                        [% END %]
                    [% END %]
                    <li>
                        <a class="btn btn-primary" href="/cgi-bin/koha/ill/ill-requests.pl?[% get_params %]">Place request with IncDocs</a>
                    </li>
            [% END %]
                <li>
                    <a href="/cgi-bin/koha/ill/ill-requests.pl?op=illview&amp;illrequest_id=[% whole.illrequest_id %]">Return to request</a>
                </li>
            [% IF incdocsRsp && !whole.backend_availability.error %]
                <h3>IncDocs availability response details:</h2>
                [% FOREACH item IN incdocsRsp %]
                    <tr>
                    <td style="padding: 5px"><strong>[% item.key %]</strong></td>
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
            </ol>
            </table>
        </div>
    [% END %]
</div>