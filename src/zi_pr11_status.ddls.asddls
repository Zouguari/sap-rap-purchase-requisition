@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PR v2 - Status'
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZI_PR11_Status
  as select from zpr11_status
{
      @ObjectModel.text.element: ['StatusText']
  key status      as Status,
      @Semantics.text: true
      status_text as StatusText,
      criticality as Criticality
}
