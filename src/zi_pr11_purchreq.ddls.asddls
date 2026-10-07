@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PR v2 - Purchase Request'
define root view entity ZI_PR11_PurchReq
  as select from zpr11_hdr
  composition [0..*] of ZI_PR11_PurchReqItem as _Item
  association [0..1] to I_Plant           as _Plant
    on $projection.Plant = _Plant.Plant
  association [0..1] to I_PurchasingGroup as _PurchasingGroup
    on $projection.PurchasingGroup = _PurchasingGroup.PurchasingGroup
  association [0..1] to ZI_PR11_Status    as _StatusInfo
    on $projection.Status = _StatusInfo.Status
  association [0..1] to ZI_PR11_Approver  as _CurrentApprover
    on _CurrentApprover.Approver = $session.user
{
  key pr_uuid               as PrUuid,
      pr_id                 as PrId,
      description           as Description,
      requester             as Requester,
      plant                 as Plant,
      purchasing_group      as PurchasingGroup,
      status                as Status,
      @Semantics.amount.currencyCode: 'Currency'
      total_amount          as TotalAmount,
      currency              as Currency,
      approved_by           as ApprovedBy,
      approved_at           as ApprovedAt,
      reject_reason         as RejectReason,
      sap_pr_number         as SapPrNumber,
      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by       as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Item,
      _Plant,
      _PurchasingGroup,
      _StatusInfo,
      _CurrentApprover
}
