@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PR v2 - Purchase Request Item (Projection)'
@Metadata.allowExtensions: true
define view entity ZC_PR11_PurchReqItem
  as projection on ZI_PR11_PurchReqItem
{
  key PrUuid,
  key ItemUuid,
      ItemNo,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_PR11_MaterialVH', element: 'Material' } }]
      Material,
      Description,
      Quantity,
      Unit,
      UnitPrice,
      ItemAmount,
      Currency,
      DeliveryDate,
      LocalLastChangedAt,

      _PurchReq : redirected to parent ZC_PR11_PurchReq,
      _Product
}
