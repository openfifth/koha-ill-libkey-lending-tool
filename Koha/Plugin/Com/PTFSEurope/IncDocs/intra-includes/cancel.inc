[% IF whole.error %]
    <p class="alert alert-warning">[% whole.message || 'Unhandled error' %]</p>
[% END %]

[% IF whole.stage == "confirm" %]
    <h2>Cancel manual request</h2>
    <p>A cancellation will be sent to the supplying agency (<strong>[% whole.supplyingAgencyName | html %]</strong>) notifying that we no longer expect this request to be fulfilled.</p>
    <p>Proceeding with this action will set this request to 'Cancellation requested' and allow it to be placed again with a different library.</p>
    <p>
        [% base_url = "/cgi-bin/koha/ill/ill-requests.pl" %]
        [% proceed_url = base_url _ "?op=cancel&stage=confirm" _ "&illrequest_id=" _ request.illrequest_id %]
        [% cancel_url = base_url _ "?op=illview&illrequest_id=" _ request.illrequest_id %]
        <a class="btn btn-sm btn-primary" href="[% proceed_url | url %]">Revert request</a>
        <a class="btn btn-sm btn-default cancel" href="[% cancel_url | url %]">Cancel</a>
    </p>
[% END %]
