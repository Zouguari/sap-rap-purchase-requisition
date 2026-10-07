@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PR v2 - Purchase Request Item'
define view entity ZI_PR11_PurchReqItem
  as select from zpr11_itm
  association to parent ZI_PR11_PurchReq as _PurchReq
    on $projection.PrUuid = _PurchReq.PrUuid
  association [0..1] to I_Product        as _Product
    on $projection.Material = _Product.Product
{
  key pr_uuid               as PrUuid,
  key item_uuid             as ItemUuid,
      item_no               as ItemNo,
      material              as Material,
      description           as Description,
      @Semantics.quantity.unitOfMeasure: 'Unit'
      quantity              as Quantity,
      unit                  as Unit,
      @Semantics.amount.currencyCode: 'Currency'
      unit_price            as UnitPrice,
      @Semantics.amount.currencyCode: 'Currency'
      item_amount           as ItemAmount,
      currency              as Currency,
      delivery_date         as DeliveryDate,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _PurchReq,
      _Product
}
