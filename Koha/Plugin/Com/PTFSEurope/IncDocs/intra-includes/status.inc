[% USE Koha %]
[% value = whole.value %]
<div class="page-section">
      <div class="rows">
          <table border="1" cellpadding="5" cellspacing="0">
          <ol>
            [% IF value.request_status == 'REQ' %]
                [% IF value.status == 'pending' %]
                    <h3 class="text-warning">IncDocs status is still pending</h3>
                [% ELSIF value.status == 'complete' %]
                    <h3 class="text-success">IncDocs status is now complete</h3>
                [% ELSIF value.status == 'declined' %]
                    <h3 class="text-danger">IncDocs status is now declined</h3>
                [% END %]
            [% END %]
              <li>
                  <a href="/cgi-bin/koha/ill/ill-requests.pl?op=illview&amp;illrequest_id=[% value.illrequest_id %]">Return to request</a>
              </li>
          [% IF value %]
              <h3>IncDocs status response details:</h2>
              [% FOREACH item IN value %]
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
</div>