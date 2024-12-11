[% USE Koha %]
[% incdocsRsp = whole.backend_availability.response.data %]
[% IF whole.stage == "availability" %]
<table border="1" cellpadding="5" cellspacing="0">
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
</table>
[% END %]