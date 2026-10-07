@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PR v2 - Purchase Request (Projection)'
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZC_PR11_PurchReq
  as projection on ZI_PR11_PurchReq
{
  key PrUuid,
      @Search.defaultSearchElement: true
      PrId,
      @Search.defaultSearchElement: true
      Description,
      Requester,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_Plant', element: 'Plant' } }]
      Plant,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_PurchasingGroup', element: 'PurchasingGroup' } }]
      PurchasingGroup,
      @ObjectModel.text.element: ['StatusText']
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_PR11_Status', element: 'Status' } }]
      Status,
      _StatusInfo.StatusText  as StatusText,
      _StatusInfo.Criticality as StatusCriticality,
      TotalAmount,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_Currency', element: 'Currency' } }]
      Currency,
      ApprovedBy,
      ApprovedAt,
      RejectReason,
      SapPrNumber,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,

      _Item : redirected to composition child ZC_PR11_PurchReqItem,
      _Plant,
      _PurchasingGroup,
      _CurrentApprover
}
