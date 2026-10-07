CLASS zcl_pr11_test_data DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS:
      c_other_requester TYPE syuname VALUE 'TRAIN-12',
      c_material        TYPE matnr   VALUE 'FG29',
      c_plant           TYPE werks_d VALUE '1010',
      c_purch_group     TYPE ekgrp   VALUE '001',
      c_currency        TYPE waers   VALUE 'EUR'.

    METHODS fill_status_texts.

    METHODS create_request
      IMPORTING iv_pr_id       TYPE zpr11_hdr-pr_id
                iv_description TYPE zpr11_hdr-description
                iv_quantity    TYPE zpr11_itm-quantity
                iv_unit_price  TYPE zpr11_itm-unit_price
      RAISING   cx_uuid_error.

ENDCLASS.


CLASS zcl_pr11_test_data IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA ls_approver TYPE zpr11_appr.

    " 0) Status texts and criticality (0 neutral, 1 red, 2 orange, 3 green)
    fill_status_texts( ).

    " 1) Remove previous test data
    DELETE FROM zpr11_itm
      WHERE pr_uuid IN ( SELECT pr_uuid FROM zpr11_hdr
                           WHERE description LIKE '[TEST]%' ).
    DELETE FROM zpr11_hdr WHERE description LIKE '[TEST]%'.

    " 2) Register the current user as approver with a limit of 5,000 EUR
    ls_approver-approver       = cl_abap_context_info=>get_user_technical_name( ).
    ls_approver-approval_limit = '5000.00'.
    ls_approver-currency       = c_currency.
    MODIFY zpr11_appr FROM @ls_approver.

    " 3) Submitted requests created by another user
    TRY.
        SELECT MAX( pr_id ) FROM zpr11_hdr INTO @DATA(lv_max_id).

        create_request( iv_pr_id       = CONV #( lv_max_id + 1 )
                        iv_description = '[TEST] Laptops for new hires'
                        iv_quantity    = 3
                        iv_unit_price  = '100.00' ).

        create_request( iv_pr_id       = CONV #( lv_max_id + 2 )
                        iv_description = '[TEST] Office chairs'
                        iv_quantity    = 9
                        iv_unit_price  = '50.00' ).

        create_request( iv_pr_id       = CONV #( lv_max_id + 3 )
                        iv_description = '[TEST] Production line spare parts'
                        iv_quantity    = 80
                        iv_unit_price  = '100.00' ).

        COMMIT WORK.

        out->write( |Status texts filled| ).
        out->write( |Approver { ls_approver-approver } registered (limit 5,000 EUR)| ).
        out->write( |3 submitted test requests created for { c_other_requester }| ).

      CATCH cx_uuid_error INTO DATA(lx_uuid).
        ROLLBACK WORK.
        out->write( lx_uuid->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD fill_status_texts.
    DATA lt_status TYPE STANDARD TABLE OF zpr11_status WITH DEFAULT KEY.

    lt_status = VALUE #(
      ( status = 'N' status_text = 'New'       criticality = 0 )
      ( status = 'S' status_text = 'Submitted' criticality = 2 )
      ( status = 'A' status_text = 'Approved'  criticality = 3 )
      ( status = 'R' status_text = 'Rejected'  criticality = 1 ) ).

    MODIFY zpr11_status FROM TABLE @lt_status.
  ENDMETHOD.

  METHOD create_request.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    " Unit and description from the material master
    SELECT SINGLE BaseUnit, MaterialDescription
      FROM zi_pr11_materialvh
      WHERE Material = @c_material
      INTO @DATA(ls_material).

    DATA(lv_pr_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
    DATA(lv_amount)  = CONV zpr11_hdr-total_amount( iv_quantity * iv_unit_price ).

    DATA(ls_header) = VALUE zpr11_hdr(
      pr_uuid               = lv_pr_uuid
      pr_id                 = iv_pr_id
      description           = iv_description
      requester             = c_other_requester
      plant                 = c_plant
      purchasing_group      = c_purch_group
      status                = 'S'
      total_amount          = lv_amount
      currency              = c_currency
      created_by            = c_other_requester
      created_at            = lv_now
      last_changed_by       = c_other_requester
      last_changed_at       = lv_now
      local_last_changed_at = lv_now ).
    INSERT zpr11_hdr FROM @ls_header.

    DATA(ls_item) = VALUE zpr11_itm(
      pr_uuid               = lv_pr_uuid
      item_uuid             = cl_system_uuid=>create_uuid_x16_static( )
      item_no               = '00010'
      material              = c_material
      description           = ls_material-MaterialDescription
      quantity              = iv_quantity
      unit                  = ls_material-BaseUnit
      unit_price            = iv_unit_price
      item_amount           = lv_amount
      currency              = c_currency
      delivery_date         = cl_abap_context_info=>get_system_date( ) + 14
      local_last_changed_at = lv_now ).
    INSERT zpr11_itm FROM @ls_item.
  ENDMETHOD.

ENDCLASS.
