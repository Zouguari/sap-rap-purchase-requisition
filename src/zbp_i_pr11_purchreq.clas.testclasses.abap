"! Unit tests for the purchase request business object
"! @testing ZI_PR11_PURCHREQ
CLASS ltc_purchase_request DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_item,
        quantity   TYPE menge_d,
        unit_price TYPE zpr11_itm-unit_price,
      END OF ty_item,
      tt_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    CONSTANTS:
      c_material    TYPE matnr   VALUE 'FG29',
      c_plant       TYPE werks_d VALUE '1010',
      c_purch_group TYPE ekgrp   VALUE '001'.

    CLASS-DATA go_sql_environment TYPE REF TO if_osql_test_environment.

    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS teardown.

    METHODS create_request
      IMPORTING it_items          TYPE tt_items
                iv_draft          TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_pr_uuid) TYPE sysuuid_x16.

    METHODS create_sets_defaults           FOR TESTING.
    METHODS amounts_and_total              FOR TESTING.
    METHODS delete_item_recalculates_total FOR TESTING.
    METHODS submit_without_items_fails     FOR TESTING.
    METHODS submit_sets_status_submitted   FOR TESTING.
    METHODS own_request_cannot_be_approved FOR TESTING.
    METHODS save_rejects_zero_quantity     FOR TESTING.

ENDCLASS.


CLASS ltc_purchase_request IMPLEMENTATION.

  METHOD class_setup.
    " Approvers table is replaced by a test double
    go_sql_environment = cl_osql_test_environment=>create(
                           i_dependency_list = VALUE #( ( 'ZPR11_APPR' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    go_sql_environment->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA lt_approvers TYPE STANDARD TABLE OF zpr11_appr WITH EMPTY KEY.

    go_sql_environment->clear_doubles( ).

    " The current user is an approver without limit
    lt_approvers = VALUE #( ( approver       = cl_abap_context_info=>get_user_technical_name( )
                              approval_limit = 0
                              currency       = 'EUR' ) ).
    go_sql_environment->insert_test_data( lt_approvers ).
  ENDMETHOD.

  METHOD teardown.
    " Discard the transactional buffer
    ROLLBACK ENTITIES.
  ENDMETHOD.

  METHOD create_request.
    DATA(lv_draft) = COND abp_behv_flag( WHEN iv_draft = abap_true
                                           THEN if_abap_behv=>mk-on
                                         ELSE if_abap_behv=>mk-off ).
    DATA(lv_delivery_date) = CONV dats( cl_abap_context_info=>get_system_date( ) + 7 ).

    IF it_items IS INITIAL.
      MODIFY ENTITIES OF zi_pr11_purchreq
        ENTITY PurchaseRequest
          CREATE FIELDS ( Description Plant PurchasingGroup )
          WITH VALUE #( ( %cid            = 'PR'
                          %is_draft       = lv_draft
                          Description     = 'Unit test request'
                          Plant           = c_plant
                          PurchasingGroup = c_purch_group ) )
        MAPPED DATA(ls_mapped_header)
        FAILED DATA(ls_failed_header).

      cl_abap_unit_assert=>assert_initial( act = ls_failed_header
                                           msg = 'Request creation failed' ).
      rv_pr_uuid = ls_mapped_header-purchaserequest[ 1 ]-PrUuid.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        CREATE FIELDS ( Description Plant PurchasingGroup )
        WITH VALUE #( ( %cid            = 'PR'
                        %is_draft       = lv_draft
                        Description     = 'Unit test request'
                        Plant           = c_plant
                        PurchasingGroup = c_purch_group ) )
        CREATE BY \_Item
        FIELDS ( Material Quantity UnitPrice DeliveryDate )
        WITH VALUE #( ( %cid_ref  = 'PR'
                        %is_draft = lv_draft
                        %target   = VALUE #( FOR ls_item IN it_items INDEX INTO lv_index
                                             ( %cid         = |ITEM{ lv_index }|
                                               %is_draft    = lv_draft
                                               Material     = c_material
                                               Quantity     = ls_item-quantity
                                               UnitPrice    = ls_item-unit_price
                                               DeliveryDate = lv_delivery_date ) ) ) )
      MAPPED DATA(ls_mapped)
      FAILED DATA(ls_failed).

    cl_abap_unit_assert=>assert_initial( act = ls_failed
                                         msg = 'Request creation failed' ).
    rv_pr_uuid = ls_mapped-purchaserequest[ 1 ]-PrUuid.
  ENDMETHOD.

  METHOD create_sets_defaults.
    DATA(lv_pr_uuid) = create_request( VALUE #( ( quantity = 5 unit_price = '20.00' ) ) ).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        FIELDS ( Status Requester Currency )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_requests).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemNo Unit Currency )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_items).

    DATA(ls_request) = lt_requests[ 1 ].
    DATA(ls_item)    = lt_items[ 1 ].

    cl_abap_unit_assert=>assert_equals( act = ls_request-Status    exp = 'N'
                                        msg = 'Initial status must be New' ).
    cl_abap_unit_assert=>assert_equals( act = ls_request-Requester
                                        exp = cl_abap_context_info=>get_user_technical_name( )
                                        msg = 'Requester must be the current user' ).
    cl_abap_unit_assert=>assert_equals( act = ls_request-Currency  exp = 'EUR'
                                        msg = 'Default currency must be EUR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_item-ItemNo       exp = '00010'
                                        msg = 'First item must be number 10' ).
    cl_abap_unit_assert=>assert_not_initial( act = ls_item-Unit
                                             msg = 'Unit must be taken from the material master' ).
    cl_abap_unit_assert=>assert_equals( act = ls_item-Currency     exp = 'EUR'
                                        msg = 'Item currency must be the request currency' ).
  ENDMETHOD.

  METHOD amounts_and_total.
    DATA(lv_pr_uuid) = create_request( VALUE #( ( quantity = 5 unit_price = '20.00' )
                                                ( quantity = 2 unit_price = '50.00' ) ) ).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        FIELDS ( TotalAmount )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_requests).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemNo ItemAmount )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_items).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_items ) exp = 2
                                        msg = 'Two items expected' ).
    cl_abap_unit_assert=>assert_equals( act = lt_items[ ItemNo = '00010' ]-ItemAmount
                                        exp = '100.00'
                                        msg = 'Item 10: 5 x 20 = 100' ).
    cl_abap_unit_assert=>assert_equals( act = lt_items[ ItemNo = '00020' ]-ItemAmount
                                        exp = '100.00'
                                        msg = 'Item 20: 2 x 50 = 100' ).
    cl_abap_unit_assert=>assert_equals( act = lt_requests[ 1 ]-TotalAmount
                                        exp = '200.00'
                                        msg = 'Total must be the sum of the items' ).
  ENDMETHOD.

  METHOD delete_item_recalculates_total.
    DATA(lv_pr_uuid) = create_request( VALUE #( ( quantity = 5 unit_price = '20.00' )
                                                ( quantity = 2 unit_price = '50.00' ) ) ).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemNo )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_items).

    DATA(ls_item_20) = lt_items[ ItemNo = '00020' ].

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequestItem
        DELETE FROM VALUE #( ( PrUuid   = ls_item_20-PrUuid
                               ItemUuid = ls_item_20-ItemUuid ) )
      FAILED DATA(ls_failed).

    cl_abap_unit_assert=>assert_initial( act = ls_failed
                                         msg = 'Item deletion failed' ).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        FIELDS ( TotalAmount )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_requests).

    cl_abap_unit_assert=>assert_equals( act = lt_requests[ 1 ]-TotalAmount
                                        exp = '100.00'
                                        msg = 'Total must be recalculated after deletion' ).
  ENDMETHOD.

  METHOD submit_without_items_fails.
    DATA(lv_pr_uuid) = create_request( VALUE #( ) ).

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        EXECUTE submit FROM VALUE #( ( PrUuid = lv_pr_uuid ) )
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    cl_abap_unit_assert=>assert_not_initial( act = ls_failed-purchaserequest
                                             msg = 'Submit without items must fail' ).
    cl_abap_unit_assert=>assert_not_initial( act = ls_reported-purchaserequest
                                             msg = 'An error message must be returned' ).
  ENDMETHOD.

  METHOD submit_sets_status_submitted.
    DATA(lv_pr_uuid) = create_request( VALUE #( ( quantity = 1 unit_price = '10.00' ) ) ).

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        EXECUTE submit FROM VALUE #( ( PrUuid = lv_pr_uuid ) )
      FAILED DATA(ls_failed).

    cl_abap_unit_assert=>assert_initial( act = ls_failed
                                         msg = 'Submit must succeed' ).

    READ ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        FIELDS ( Status )
        WITH VALUE #( ( PrUuid = lv_pr_uuid ) )
      RESULT DATA(lt_requests).

    cl_abap_unit_assert=>assert_equals( act = lt_requests[ 1 ]-Status exp = 'S'
                                        msg = 'Status must be Submitted' ).
  ENDMETHOD.

  METHOD own_request_cannot_be_approved.
    " The current user is an approver (test double) but also the requester
    DATA(lv_pr_uuid) = create_request( VALUE #( ( quantity = 1 unit_price = '10.00' ) ) ).

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        EXECUTE submit FROM VALUE #( ( PrUuid = lv_pr_uuid ) )
      FAILED DATA(ls_failed_submit).

    cl_abap_unit_assert=>assert_initial( act = ls_failed_submit
                                         msg = 'Submit must succeed' ).

    MODIFY ENTITIES OF zi_pr11_purchreq
      ENTITY PurchaseRequest
        EXECUTE approve FROM VALUE #( ( PrUuid = lv_pr_uuid ) )
      FAILED DATA(ls_failed_approve).

    cl_abap_unit_assert=>assert_not_initial( act = ls_failed_approve-purchaserequest
                                             msg = 'Approving one''s own request must be refused' ).
  ENDMETHOD.

  METHOD save_rejects_zero_quantity.
    " The save must be refused by validateItem: nothing is written to the database
    create_request( VALUE #( ( quantity = 0 unit_price = '10.00' ) ) ).

    COMMIT ENTITIES
      RESPONSE OF zi_pr11_purchreq
        FAILED   DATA(ls_failed)
        REPORTED DATA(ls_reported).

    cl_abap_unit_assert=>assert_not_initial( act = ls_failed-purchaserequestitem
                                             msg = 'Saving a quantity of 0 must be refused' ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( line_exists( ls_reported-purchaserequestitem[ %element-Quantity = if_abap_behv=>mk-on ] ) )
      msg = 'An error message must be bound to the Quantity field' ).
  ENDMETHOD.

ENDCLASS.
