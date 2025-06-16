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
                    [% IF whole.found_locally %] locally (at the requesting library) [% END %]
                </h3>
                    [% IF ( whole.found_locally ) %]
                        <div>This article was found locally and will not be placed with IncDocs, the article link will be directly sent to the patron instead.</div>
                    [% END %]
                    [% SET get_params = "op=" _ whole.method _ "&stage=" _ whole.future _ "&illrequest_id=" _ whole.illrequest_id %]
                    [% FOREACH key IN incdocsRsp.keys %]
                        [% value = incdocsRsp.$key %]
                        [% IF key != 'op' && key != 'method' && key != 'custom_key' && key != 'custom_value' && key != 'csrf_token' %]
                            [% value = value | uri %]
                            [% get_params = get_params _ "&" _ key _ "=" _ value %]
                        [% END %]
                    [% END %]
                    <li>
                        [% IF ( whole.found_locally ) %]
                            <a class="mb-2 btn btn-primary" href="/cgi-bin/koha/ill/ill-requests.pl?[% get_params %]">
                                <i class="fa-solid fa-paper-plane"></i> Send article email to patron
                            </a>
                        [% ELSE %]
                            <a class="btn btn-primary" href="/cgi-bin/koha/ill/ill-requests.pl?[% get_params %]">
                                <i class="fa-solid fa-check"></i> Place request with IncDocs
                            </a>
                        [% END %]
                    </li>
                    [% IF ( whole.found_locally ) %]
                        <div class="mt-2">Problem with the article link?</div>
                        <li>
                            <a class="mb-2 btn btn-primary" href="/cgi-bin/koha/ill/ill-requests.pl?[% "op=confirm&illrequest_id=" _ whole.illrequest_id _ "&forceIll=1" %]">
                                <i class="fa-solid fa-repeat"></i> Force a new library request
                            </a>
                        </li>
                    [% END %]
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
                            <strong>[% subitem.key %]</strong> :
                            [% IF subitem.value.match('^http') %]
                                <a target="_blank" href="[% subitem.value | url %]">[% subitem.value %]</a>
                            [% ELSE %]
                                [% subitem.value %]
                            [% END %]
                            <br>
                        [% END %]
                    [% ELSE %]
                      [% IF item.value.match('^http') %]
                          <a target="_blank" href="[% item.value | url %]">[% item.value %]</a>
                      [% ELSE %]
                        [% item.value %]
                      [% END %]
                    [% END %]
                    </tr>
                [% END %]
            [% END %]
            </ol>
            </table>
        </div>
    [% END %]
</div>