[% USE Koha %]
[% incdocsRsp = whole.value %]
<div class="page-section">
      <div class="rows">
          <table border="1" cellpadding="5" cellspacing="0">
          <ol>
          TODO: Show message if request status has changed or not
              <li>
                  <a href="/cgi-bin/koha/ill/ill-requests.pl?op=illview&amp;illrequest_id=[% incdocsRsp.illrequest_id %]">Return to request</a>
              </li>
          [% IF incdocsRsp %]
              <h3>IncDocs status response details:</h2>
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
          </ol>
          </table>
      </div>
</div>