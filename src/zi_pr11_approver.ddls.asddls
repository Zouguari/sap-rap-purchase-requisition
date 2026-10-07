@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PR v2 - Approver'
define view entity ZI_PR11_Approver
  as select from zpr11_appr
{
  key approver       as Approver,
      @Semantics.amount.currencyCode: 'Currency'
      approval_limit as ApprovalLimit,
      currency       as Currency
}
