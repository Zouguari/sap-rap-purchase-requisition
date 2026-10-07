@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PR v2 - Material value help'
@Search.searchable: true
define view entity ZI_PR11_MaterialVH
  as select from    mara
    left outer join makt on  makt.matnr = mara.matnr
                         and makt.spras = $session.system_language
{
      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      @ObjectModel.text.element: ['MaterialDescription']
  key mara.matnr as Material,
      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      @Semantics.text: true
      makt.maktx as MaterialDescription,
      mara.meins as BaseUnit,
      mara.mtart as MaterialType
}
