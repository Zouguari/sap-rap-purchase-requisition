"! Purchase request status values
INTERFACE lif_pr_status.
  CONSTANTS:
    new       TYPE c LENGTH 1 VALUE 'N',
    submitted TYPE c LENGTH 1 VALUE 'S',
    approved  TYPE c LENGTH 1 VALUE 'A',
    rejected  TYPE c LENGTH 1 VALUE 'R'.
ENDINTERFACE.

*----------------------------------------------------------------------*
* Handler: Purchase Request (root)
*----------------------------------------------------------------------*
CLASS lhc_PurchaseRequest DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR PurchaseRequest RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR PurchaseRequest RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR PurchaseRequest RESULT result.

    METHODS submit FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequest~submit RESULT result.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequest~approve RESULT result.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequest~reject RESULT result.

    METHODS setInitialValues FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequest~setInitialValues.

    METHODS propagateCurrency FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequest~propagateCurrency.

    METHODS assignPrId FOR DETERMINE ON SAVE
      IMPORTING keys FOR PurchaseRequest~assignPrId.

    METHODS validateHeader FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseRequest~validateHeader.

    METHODS earlynumbering_cba_Item FOR NUMBERING
      IMPORTING entities FOR CREATE PurchaseRequest\_Item.

ENDCLASS.

CLASS lhc_PurchaseRequest IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Everybody may create purchase requests; finer checks are instance-based
    IF requested_authorizations-%create = if_abap_behv=>mk-on.
      result-%create = if_abap_behv=>auth-allowed.
    ENDIF.
    IF requested_authorizations-%update = if_abap_behv=>mk-on.
      result-%update = if_abap_behv=>auth-allowed.
    ENDIF.
    IF requested_authorizations-%delete = if_abap_behv=>mk-on.
      result-%delete = if_abap_behv=>auth-allowed.
    ENDIF.
  ENDMETHOD.

  METHOD get_instance_authorizations.
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( Requester TotalAmount )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests)
      FAILED failed.

    " Is the current user a registered approver, and up to which amount?
    SELECT SINGLE approval_limit
      FROM zpr11_appr
      WHERE approver = @lv_user
      INTO @DATA(lv_limit).
    DATA(lv_is_approver) = xsdbool( sy-subrc = 0 ).

    LOOP AT lt_requests INTO DATA(ls_request).
      DATA(lv_is_requester) = xsdbool( ls_request-Requester = lv_user ).

      " Segregation of duties: an approver never approves his own request
      " An approval limit of 0 means "no limit"
      DATA(lv_can_approve) = xsdbool(
            lv_is_approver  = abap_true
        AND lv_is_requester = abap_false
        AND ( lv_limit IS INITIAL OR ls_request-TotalAmount <= lv_limit ) ).

      DATA(lv_requester_auth) = COND #(
        WHEN lv_is_requester = abap_true THEN if_abap_behv=>auth-allowed
        ELSE if_abap_behv=>auth-unauthorized ).

      DATA(lv_approver_auth) = COND #(
        WHEN lv_can_approve = abap_true THEN if_abap_behv=>auth-allowed
        ELSE if_abap_behv=>auth-unauthorized ).

      APPEND VALUE #( %tky            = ls_request-%tky
                      %update         = lv_requester_auth
                      %delete         = lv_requester_auth
                      %assoc-_Item    = lv_requester_auth
                      %action-submit  = lv_requester_auth
                      %action-approve = lv_approver_auth
                      %action-reject  = lv_approver_auth ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests)
      FAILED failed.

    LOOP AT lt_requests INTO DATA(ls_request).
      DATA(lv_when_new) = COND #(
        WHEN ls_request-Status = lif_pr_status=>new OR ls_request-Status IS INITIAL
          THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_when_submitted) = COND #(
        WHEN ls_request-Status = lif_pr_status=>submitted
          THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      APPEND VALUE #( %tky            = ls_request-%tky
                      %update         = lv_when_new
                      %delete         = lv_when_new
                      %assoc-_Item    = lv_when_new
                      %action-Edit    = lv_when_new
                      %action-submit  = lv_when_new
                      %action-approve = lv_when_submitted
                      %action-reject  = lv_when_submitted ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD submit.
    " A request can only be submitted if it has at least one item
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemUuid )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items)
      LINK DATA(lt_links).

    DATA lt_update TYPE TABLE FOR UPDATE zi_pr11_purchreq\\PurchaseRequest.

    LOOP AT keys INTO DATA(ls_key).
      IF NOT line_exists( lt_links[ source-PrUuid    = ls_key-PrUuid
                                    source-%is_draft = ls_key-%is_draft ] ).
        APPEND VALUE #( %tky = ls_key-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky = ls_key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Add at least one item before submitting' ) )
          TO reported-purchaserequest.
      ELSE.
        APPEND VALUE #( %tky   = ls_key-%tky
                        Status = lif_pr_status=>submitted ) TO lt_update.
      ENDIF.
    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
        ENTITY PurchaseRequest
          UPDATE FIELDS ( Status )
          WITH lt_update.
    ENDIF.

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_result).

    result = VALUE #( FOR ls_result IN lt_result
                      ( %tky = ls_result-%tky %param = ls_result ) ).
  ENDMETHOD.

  METHOD approve.
    DATA lv_timestamp TYPE timestampl.
    GET TIME STAMP FIELD lv_timestamp.
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    " The SAP purchase requisition is created in the save phase (saver class)
    MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        UPDATE FIELDS ( Status ApprovedBy ApprovedAt )
        WITH VALUE #( FOR ls_key IN keys
                      ( %tky       = ls_key-%tky
                        Status     = lif_pr_status=>approved
                        ApprovedBy = lv_user
                        ApprovedAt = lv_timestamp ) ).

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_result).

    result = VALUE #( FOR ls_result IN lt_result
                      ( %tky = ls_result-%tky %param = ls_result ) ).
  ENDMETHOD.

  METHOD reject.
    DATA lt_update TYPE TABLE FOR UPDATE zi_pr11_purchreq\\PurchaseRequest.

    LOOP AT keys INTO DATA(ls_key).
      IF ls_key-%param-RejectReason IS INITIAL.
        APPEND VALUE #( %tky = ls_key-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky = ls_key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'A rejection reason is required' ) )
          TO reported-purchaserequest.
      ELSE.
        APPEND VALUE #( %tky         = ls_key-%tky
                        Status       = lif_pr_status=>rejected
                        RejectReason = ls_key-%param-RejectReason ) TO lt_update.
      ENDIF.
    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
        ENTITY PurchaseRequest
          UPDATE FIELDS ( Status RejectReason )
          WITH lt_update.
    ENDIF.

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_result).

    result = VALUE #( FOR ls_result IN lt_result
                      ( %tky = ls_result-%tky %param = ls_result ) ).
  ENDMETHOD.

  METHOD setInitialValues.
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( Status Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    DELETE lt_requests WHERE Status IS NOT INITIAL.
    CHECK lt_requests IS NOT INITIAL.

    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    " Setting the currency also triggers propagateCurrency for the items
    MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        UPDATE FIELDS ( Status Requester Currency )
        WITH VALUE #( FOR ls_request IN lt_requests
                      ( %tky      = ls_request-%tky
                        Status    = lif_pr_status=>new
                        Requester = lv_user
                        Currency  = COND #( WHEN ls_request-Currency IS INITIAL
                                              THEN 'EUR'
                                            ELSE ls_request-Currency ) ) ).
  ENDMETHOD.

  METHOD propagateCurrency.
    " The currency of the request is always the currency of all its items
    DATA lt_update   TYPE TABLE FOR UPDATE zi_pr11_purchreq\\PurchaseRequestItem.
    DATA lv_currency TYPE waers.

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    LOOP AT lt_items INTO DATA(ls_item).
      lv_currency = VALUE #( lt_requests[ PrUuid    = ls_item-PrUuid
                                          %is_draft = ls_item-%is_draft ]-Currency OPTIONAL ).
      IF ls_item-Currency <> lv_currency.
        APPEND VALUE #( %tky     = ls_item-%tky
                        Currency = lv_currency ) TO lt_update.
      ENDIF.
    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
        ENTITY PurchaseRequestItem
          UPDATE FIELDS ( Currency )
          WITH lt_update.
    ENDIF.
  ENDMETHOD.

  METHOD assignPrId.
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( PrId )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    DELETE lt_requests WHERE PrId IS NOT INITIAL.
    CHECK lt_requests IS NOT INITIAL.

    " Simple sequential numbering (a number range object would be used in production)
    SELECT MAX( pr_id ) FROM zpr11_hdr INTO @DATA(lv_max_id).

    MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        UPDATE FIELDS ( PrId )
        WITH VALUE #( FOR ls_request IN lt_requests INDEX INTO lv_index
                      ( %tky = ls_request-%tky
                        PrId = lv_max_id + lv_index ) ).
  ENDMETHOD.

  METHOD validateHeader.
    DATA lv_exists TYPE abap_bool.

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        FIELDS ( Description Plant PurchasingGroup Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    LOOP AT lt_requests INTO DATA(ls_request).
      " Clear messages of a previous validation run (draft)
      APPEND VALUE #( %tky        = ls_request-%tky
                      %state_area = 'VALIDATE_HEADER' ) TO reported-purchaserequest.

      IF ls_request-Description IS INITIAL.
        APPEND VALUE #( %tky = ls_request-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky                 = ls_request-%tky
                        %state_area          = 'VALIDATE_HEADER'
                        %msg                 = new_message_with_text(
                                                 severity = if_abap_behv_message=>severity-error
                                                 text     = 'Description is required' )
                        %element-Description = if_abap_behv=>mk-on ) TO reported-purchaserequest.
      ENDIF.

      CLEAR lv_exists.
      SELECT SINGLE @abap_true FROM I_Plant
        WHERE Plant = @ls_request-Plant
        INTO @lv_exists.
      IF lv_exists = abap_false.
        APPEND VALUE #( %tky = ls_request-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky           = ls_request-%tky
                        %state_area    = 'VALIDATE_HEADER'
                        %msg           = new_message_with_text(
                                           severity = if_abap_behv_message=>severity-error
                                           text     = |Plant '{ ls_request-Plant }' does not exist| )
                        %element-Plant = if_abap_behv=>mk-on ) TO reported-purchaserequest.
      ENDIF.

      CLEAR lv_exists.
      SELECT SINGLE @abap_true FROM I_PurchasingGroup
        WHERE PurchasingGroup = @ls_request-PurchasingGroup
        INTO @lv_exists.
      IF lv_exists = abap_false.
        APPEND VALUE #( %tky = ls_request-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky                     = ls_request-%tky
                        %state_area              = 'VALIDATE_HEADER'
                        %msg                     = new_message_with_text(
                                                     severity = if_abap_behv_message=>severity-error
                                                     text     = |Purchasing group '{ ls_request-PurchasingGroup }' does not exist| )
                        %element-PurchasingGroup = if_abap_behv=>mk-on ) TO reported-purchaserequest.
      ENDIF.

      CLEAR lv_exists.
      SELECT SINGLE @abap_true FROM I_Currency
        WHERE Currency = @ls_request-Currency
        INTO @lv_exists.
      IF lv_exists = abap_false.
        APPEND VALUE #( %tky = ls_request-%tky ) TO failed-purchaserequest.
        APPEND VALUE #( %tky              = ls_request-%tky
                        %state_area       = 'VALIDATE_HEADER'
                        %msg              = new_message_with_text(
                                              severity = if_abap_behv_message=>severity-error
                                              text     = |Currency '{ ls_request-Currency }' does not exist| )
                        %element-Currency = if_abap_behv=>mk-on ) TO reported-purchaserequest.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD earlynumbering_cba_Item.
    " Items get a UUID key; the parent key is inherited (composite key)
    LOOP AT entities INTO DATA(ls_entity).
      LOOP AT ls_entity-%target INTO DATA(ls_target).
        APPEND CORRESPONDING #( ls_target ) TO mapped-purchaserequestitem
          ASSIGNING FIELD-SYMBOL(<ls_mapped>).
        <ls_mapped>-PrUuid = ls_entity-PrUuid.
        IF <ls_mapped>-ItemUuid IS INITIAL.
          TRY.
              <ls_mapped>-ItemUuid = cl_system_uuid=>create_uuid_x16_static( ).
            CATCH cx_uuid_error.
              APPEND VALUE #( %cid      = ls_target-%cid
                              %is_draft = ls_target-%is_draft ) TO failed-purchaserequestitem.
          ENDTRY.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Handler: Purchase Request Item (child)
*----------------------------------------------------------------------*
CLASS lhc_PurchaseRequestItem DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR PurchaseRequestItem RESULT result.

    METHODS setItemDefaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequestItem~setItemDefaults.

    METHODS calculateAmounts FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequestItem~calculateAmounts.

    METHODS validateItem FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseRequestItem~validateItem.

ENDCLASS.

CLASS lhc_PurchaseRequestItem IMPLEMENTATION.

  METHOD get_instance_features.
    DATA lv_status TYPE zi_pr11_purchreq-Status.

    " Items are editable only while the request is still new
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem BY \_PurchReq
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    LOOP AT keys INTO DATA(ls_key).
      lv_status = VALUE #( lt_requests[ PrUuid    = ls_key-PrUuid
                                        %is_draft = ls_key-%is_draft ]-Status OPTIONAL ).

      DATA(lv_editable) = COND #(
        WHEN lv_status = lif_pr_status=>new OR lv_status IS INITIAL
          THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      APPEND VALUE #( %tky    = ls_key-%tky
                      %update = lv_editable
                      %delete = lv_editable ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD setItemDefaults.
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem
        FIELDS ( Material Description ItemNo Unit Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    CHECK lt_items IS NOT INITIAL.

    " Parent requests (for the currency)
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem BY \_PurchReq
        FIELDS ( Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_requests).

    " All items of these requests (for the item numbering)
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemNo )
        WITH CORRESPONDING #( lt_requests )
      RESULT DATA(lt_siblings).

    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<ls_item>).

      " Item number: highest number of the request + 10
      IF <ls_item>-ItemNo IS INITIAL.
        DATA(lv_max_no) = CONV zi_pr11_purchreqitem-ItemNo( 0 ).
        LOOP AT lt_siblings INTO DATA(ls_sibling)
             WHERE PrUuid = <ls_item>-PrUuid AND %is_draft = <ls_item>-%is_draft.
          IF ls_sibling-ItemNo > lv_max_no.
            lv_max_no = ls_sibling-ItemNo.
          ENDIF.
        ENDLOOP.
        <ls_item>-ItemNo = lv_max_no + 10.
        " Register the new number so that a second new item gets the next one
        LOOP AT lt_siblings ASSIGNING FIELD-SYMBOL(<ls_self>)
             WHERE ItemUuid = <ls_item>-ItemUuid AND %is_draft = <ls_item>-%is_draft.
          <ls_self>-ItemNo = <ls_item>-ItemNo.
        ENDLOOP.
      ENDIF.

      " Unit and description from the SAP material master
      IF <ls_item>-Material IS NOT INITIAL.
        SELECT SINGLE BaseUnit, MaterialDescription
          FROM zi_pr11_materialvh
          WHERE Material = @<ls_item>-Material
          INTO @DATA(ls_material).
        IF sy-subrc = 0.
          <ls_item>-Unit        = ls_material-BaseUnit.
          <ls_item>-Description = ls_material-MaterialDescription.
        ENDIF.
      ENDIF.

      " Currency of the request (may still be empty here; propagateCurrency completes it)
      <ls_item>-Currency = VALUE #( lt_requests[ PrUuid    = <ls_item>-PrUuid
                                                 %is_draft = <ls_item>-%is_draft ]-Currency OPTIONAL ).
    ENDLOOP.

    MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem
        UPDATE FIELDS ( ItemNo Unit Description Currency )
        WITH CORRESPONDING #( lt_items ).
  ENDMETHOD.

  METHOD calculateAmounts.
    " 1) Item amount = quantity x unit price (deleted items are simply not found)
    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem
        FIELDS ( Quantity UnitPrice )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    IF lt_items IS NOT INITIAL.
      MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
        ENTITY PurchaseRequestItem
          UPDATE FIELDS ( ItemAmount )
          WITH VALUE #( FOR ls_item IN lt_items
                        ( %tky       = ls_item-%tky
                          ItemAmount = ls_item-Quantity * ls_item-UnitPrice ) ).
    ENDIF.

    " 2) Total of each affected request. The parent key is part of the item key,
    "    so it is also available for deleted items.
    DATA lt_request_keys TYPE TABLE FOR READ IMPORT zi_pr11_purchreq\\PurchaseRequest.
    lt_request_keys = VALUE #( FOR ls_key IN keys
                               ( %is_draft = ls_key-%is_draft
                                 PrUuid    = ls_key-PrUuid ) ).
    SORT lt_request_keys BY %is_draft PrUuid.
    DELETE ADJACENT DUPLICATES FROM lt_request_keys COMPARING %is_draft PrUuid.

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest BY \_Item
        FIELDS ( ItemAmount )
        WITH CORRESPONDING #( lt_request_keys )
      RESULT DATA(lt_all_items).

    MODIFY ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequest
        UPDATE FIELDS ( TotalAmount )
        WITH VALUE #( FOR ls_request_key IN lt_request_keys
                      ( %tky        = ls_request_key-%tky
                        TotalAmount = REDUCE #( INIT lv_sum TYPE zi_pr11_purchreq-TotalAmount
                                                FOR ls_any IN lt_all_items
                                                WHERE ( PrUuid    = ls_request_key-PrUuid
                                                    AND %is_draft = ls_request_key-%is_draft )
                                                NEXT lv_sum = lv_sum + ls_any-ItemAmount ) ) ).
  ENDMETHOD.

  METHOD validateItem.
    DATA lv_exists TYPE abap_bool.
    DATA(lv_today) = cl_abap_context_info=>get_system_date( ).

    READ ENTITIES OF zi_pr11_purchreq IN LOCAL MODE
      ENTITY PurchaseRequestItem
        FIELDS ( ItemNo Material Quantity UnitPrice DeliveryDate )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    LOOP AT lt_items INTO DATA(ls_item).
      " Clear messages of a previous validation run (draft)
      APPEND VALUE #( %tky        = ls_item-%tky
                      %state_area = 'VALIDATE_ITEM'
                      %path       = VALUE #( purchaserequest-%is_draft = ls_item-%is_draft
                                             purchaserequest-PrUuid    = ls_item-PrUuid ) )
        TO reported-purchaserequestitem.

      CLEAR lv_exists.
      SELECT SINGLE @abap_true FROM zi_pr11_materialvh
        WHERE Material = @ls_item-Material
        INTO @lv_exists.
      IF lv_exists = abap_false.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-purchaserequestitem.
        APPEND VALUE #( %tky              = ls_item-%tky
                        %state_area       = 'VALIDATE_ITEM'
                        %path             = VALUE #( purchaserequest-%is_draft = ls_item-%is_draft
                                                     purchaserequest-PrUuid    = ls_item-PrUuid )
                        %msg              = new_message_with_text(
                                              severity = if_abap_behv_message=>severity-error
                                              text     = |Item { ls_item-ItemNo }: material '{ ls_item-Material }' does not exist| )
                        %element-Material = if_abap_behv=>mk-on ) TO reported-purchaserequestitem.
      ENDIF.

      IF ls_item-Quantity <= 0.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-purchaserequestitem.
        APPEND VALUE #( %tky              = ls_item-%tky
                        %state_area       = 'VALIDATE_ITEM'
                        %path             = VALUE #( purchaserequest-%is_draft = ls_item-%is_draft
                                                     purchaserequest-PrUuid    = ls_item-PrUuid )
                        %msg              = new_message_with_text(
                                              severity = if_abap_behv_message=>severity-error
                                              text     = |Item { ls_item-ItemNo }: quantity must be greater than zero| )
                        %element-Quantity = if_abap_behv=>mk-on ) TO reported-purchaserequestitem.
      ENDIF.

      IF ls_item-UnitPrice <= 0.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-purchaserequestitem.
        APPEND VALUE #( %tky               = ls_item-%tky
                        %state_area        = 'VALIDATE_ITEM'
                        %path              = VALUE #( purchaserequest-%is_draft = ls_item-%is_draft
                                                      purchaserequest-PrUuid    = ls_item-PrUuid )
                        %msg               = new_message_with_text(
                                               severity = if_abap_behv_message=>severity-error
                                               text     = |Item { ls_item-ItemNo }: unit price must be greater than zero| )
                        %element-UnitPrice = if_abap_behv=>mk-on ) TO reported-purchaserequestitem.
      ENDIF.

      IF ls_item-DeliveryDate IS INITIAL OR ls_item-DeliveryDate < lv_today.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-purchaserequestitem.
        APPEND VALUE #( %tky                  = ls_item-%tky
                        %state_area           = 'VALIDATE_ITEM'
                        %path                 = VALUE #( purchaserequest-%is_draft = ls_item-%is_draft
                                                         purchaserequest-PrUuid    = ls_item-PrUuid )
                        %msg                  = new_message_with_text(
                                                  severity = if_abap_behv_message=>severity-error
                                                  text     = |Item { ls_item-ItemNo }: delivery date must be today or later| )
                        %element-DeliveryDate = if_abap_behv=>mk-on ) TO reported-purchaserequestitem.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Saver: creation of the SAP purchase requisition (additional save)
*----------------------------------------------------------------------*
CLASS lsc_ZI_PR11_PURCHREQ DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.

  PRIVATE SECTION.
    METHODS create_sap_requisition
      IMPORTING iv_pr_uuid       TYPE sysuuid_x16
      EXPORTING ev_number        TYPE banfn
                ev_error_message TYPE string.
ENDCLASS.

CLASS lsc_ZI_PR11_PURCHREQ IMPLEMENTATION.

  METHOD save_modified.
    " Requests approved in this transaction get a standard SAP purchase requisition
    LOOP AT update-purchaserequest INTO DATA(ls_update)
         WHERE %control-Status = if_abap_behv=>mk-on
           AND Status          = lif_pr_status=>approved.

      create_sap_requisition( EXPORTING iv_pr_uuid       = ls_update-PrUuid
                              IMPORTING ev_number        = DATA(lv_number)
                                        ev_error_message = DATA(lv_error) ).

      IF lv_number IS NOT INITIAL.
        UPDATE zpr11_hdr SET sap_pr_number = @lv_number
          WHERE pr_uuid = @ls_update-PrUuid.

        APPEND VALUE #( PrUuid = ls_update-PrUuid
                        %msg   = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-success
                                   text     = |SAP purchase requisition { lv_number } created| ) )
          TO reported-purchaserequest.
      ELSE.
        APPEND VALUE #( PrUuid = ls_update-PrUuid
                        %msg   = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-warning
                                   text     = |SAP purchase requisition not created: { lv_error }| ) )
          TO reported-purchaserequest.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_sap_requisition.
    " Classic BAPI tables must use the default key (compatibility with TABLES parameters)
    DATA: ls_header  TYPE bapimereqheader,
          ls_headerx TYPE bapimereqheaderx,
          lt_items   TYPE STANDARD TABLE OF bapimereqitemimp WITH DEFAULT KEY,
          lt_itemsx  TYPE STANDARD TABLE OF bapimereqitemx WITH DEFAULT KEY,
          lt_return  TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.

    CLEAR: ev_number, ev_error_message.

    SELECT SINGLE plant, purchasing_group, requester
      FROM zpr11_hdr
      WHERE pr_uuid = @iv_pr_uuid
      INTO @DATA(ls_request).

    SELECT item_no, material, quantity, unit_price, currency, delivery_date
      FROM zpr11_itm
      WHERE pr_uuid = @iv_pr_uuid
      ORDER BY item_no
      INTO TABLE @DATA(lt_request_items).

    IF lt_request_items IS INITIAL.
      ev_error_message = 'the request has no items'.
      RETURN.
    ENDIF.

    ls_header-pr_type  = 'NB'.
    ls_headerx-pr_type = abap_true.

    " The unit is not passed: the BAPI uses the base unit of the material master
    LOOP AT lt_request_items INTO DATA(ls_item).
      APPEND VALUE #( preq_item     = ls_item-item_no
                      material_long = ls_item-material
                      plant         = ls_request-plant
                      pur_group     = ls_request-purchasing_group
                      quantity      = ls_item-quantity
                      deliv_date    = ls_item-delivery_date
                      preq_price    = ls_item-unit_price
                      price_unit    = 1
                      currency      = ls_item-currency
                      preq_name     = ls_request-requester ) TO lt_items.

      APPEND VALUE #( preq_item     = ls_item-item_no
                      preq_itemx    = abap_true
                      material_long = abap_true
                      plant         = abap_true
                      pur_group     = abap_true
                      quantity      = abap_true
                      deliv_date    = abap_true
                      preq_price    = abap_true
                      price_unit    = abap_true
                      currency      = abap_true
                      preq_name     = abap_true ) TO lt_itemsx.
    ENDLOOP.

    " The BAPI only registers its updates; they are committed together with
    " the RAP transaction (no COMMIT WORK here)
    CALL FUNCTION 'BAPI_PR_CREATE'
      EXPORTING
        prheader  = ls_header
        prheaderx = ls_headerx
      IMPORTING
        number    = ev_number
      TABLES
        return    = lt_return
        pritem    = lt_items
        pritemx   = lt_itemsx.

    LOOP AT lt_return INTO DATA(ls_return) WHERE type CA 'EA'.
      ev_error_message = ls_return-message.
      CLEAR ev_number.
      EXIT.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
