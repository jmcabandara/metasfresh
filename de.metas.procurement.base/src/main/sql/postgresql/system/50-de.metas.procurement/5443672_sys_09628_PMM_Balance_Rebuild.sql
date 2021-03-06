drop view if exists de_metas_procurement.PMM_Balance_Events_v;
create or replace view de_metas_procurement.PMM_Balance_Events_v as
	--
	-- QtyPromised, QtyOrdered
	select
		c.C_BPartner_ID
		, c.M_Product_ID
		, c.M_HU_PI_Item_Product_ID
		, c.C_Flatrate_DataEntry_ID
		--
		,  date_trunc('month', c.DatePromised) as MonthDate
		,  date_trunc('week', c.DatePromised) as WeekDate
		--
		, QtyOrdered as QtyOrdered
		, QtyOrdered_TU as QtyOrdered_TU
		, QtyPromised as QtyPromised
		, QtyPromised_TU as QtyPromised_TU
		, 0::numeric as QtyDelivered
		--
		-- , nextval('pmm_balance_seq')
		, c.AD_Client_ID as AD_Client_ID
		, 0 as AD_Org_ID
		, 'Y'::char(1) as IsActive
		, c.Created as Created
		, 0 as CreatedBy
		, c.Updated as Updated
		, 0 as UpdatedBy
	from PMM_PurchaseCandidate c
--
-- QtyDelivered
union all (
	select
		ol.C_BPartner_ID
		, ol.M_Product_ID
		, ol.M_HU_PI_Item_Product_ID
		, ol.C_Flatrate_DataEntry_ID
		--
		,  date_trunc('month', ol.DatePromised) as MonthDate
		,  date_trunc('week', ol.DatePromised) as WeekDate
		--
		, 0 as QtyOrdered
		, 0 as QtyOrdered_TU
		, 0 as QtyPromised
		, 0 as QtyPromised_TU
		, ol.QtyDelivered as QtyDelivered
		--
		, ol.AD_Client_ID as AD_Client_ID
		, 0 as AD_Org_ID
		, 'Y'::char(1) as IsActive
		, ol.Created as Created
		, 0 as CreatedBy
		, ol.Updated as Updated
		, 0 as UpdatedBy
	from C_OrderLine ol
	where true
	and ol.IsMFProcurement='Y'
)
;

-- select * from de_metas_procurement.PMM_Balance_Events_v;





























drop function if exists de_metas_procurement.PMM_Balance_Rebuild();
create or replace function de_metas_procurement.PMM_Balance_Rebuild()
returns void
AS
$BODY$
begin
	--
	--
	raise notice 'Snapshot current events';
	drop table if exists TMP_PMM_Balance_Events;
	create temporary table TMP_PMM_Balance_Events as select * from de_metas_procurement.PMM_Balance_Events_v;
	create index on TMP_PMM_Balance_Events(ad_client_id, c_bpartner_id, m_product_id, m_hu_pi_item_product_id, C_Flatrate_DataEntry_ID, MonthDate);

	--
	--
	raise notice 'Calculating weekly balances';
	drop table if exists TMP_PMM_Balance_Rebuild;
	create temporary table TMP_PMM_Balance_Rebuild as
	select
		e.C_BPartner_ID
		, e.M_Product_ID
		, e.M_HU_PI_Item_Product_ID
		, e.C_Flatrate_DataEntry_ID
		--
		,  e.MonthDate
		,  e.WeekDate
		--
		, sum(e.QtyOrdered) as QtyOrdered
		, sum(e.QtyOrdered_TU) as QtyOrdered_TU
		, sum(e.QtyPromised) as QtyPromised
		, sum(e.QtyPromised_TU) as QtyPromised_TU
		, sum(e.QtyDelivered) as QtyDelivered
		--
		, nextval('pmm_balance_seq') as PMM_Balance_ID
		, e.AD_Client_ID as AD_Client_ID
		, 0 as AD_Org_ID
		, 'Y'::char(1) as IsActive
		, min(e.Created) as Created
		, 0 as CreatedBy
		, max(e.Updated) as Updated
		, 0 as UpdatedBy
	from TMP_PMM_Balance_Events e
	group by
		e.AD_Client_ID
		, e.C_BPartner_ID
		, e.M_Product_ID
		, e.M_HU_PI_Item_Product_ID
		, e.C_Flatrate_DataEntry_ID
		, e.MonthDate
		, e.WeekDate
	;
	--
	--
	raise notice 'Calculating monthly balances';
	INSERT INTO TMP_PMM_Balance_Rebuild
	(
		c_bpartner_id
		, m_product_id
		, m_hu_pi_item_product_id
		, C_Flatrate_DataEntry_ID
		--
		, MonthDate
		, WeekDate
		--
		, QtyOrdered
		, QtyOrdered_TU
		, QtyPromised
		, QtyPromised_TU
		, QtyDelivered
		--
		, pmm_balance_id
		, ad_client_id
		, ad_org_id
		, isactive
		, created
		, createdby
		, updated
		, updatedby
	)
	select
		e.C_BPartner_ID
		, e.M_Product_ID
		, e.M_HU_PI_Item_Product_ID
		, e.C_Flatrate_DataEntry_ID
		--
		,  e.MonthDate
		,  null as WeekDate
		--
		, sum(QtyOrdered) as QtyOrdered
		, sum(QtyOrdered_TU) as QtyOrdered_TU
		, sum(QtyPromised) as QtyPromised
		, sum(QtyPromised_TU) as QtyPromised_TU
		, sum(e.QtyDelivered) as QtyDelivered
		--
		, nextval('pmm_balance_seq') as PMM_Balance_ID
		, e.AD_Client_ID as AD_Client_ID
		, 0 as AD_Org_ID
		, 'Y'::char(1) as IsActive
		, min(e.Created) as Created
		, 0 as CreatedBy
		, max(e.Updated) as Updated
		, 0 as UpdatedBy
	from TMP_PMM_Balance_Events e
	group by
		e.AD_Client_ID
		, e.C_BPartner_ID
		, e.M_Product_ID
		, e.M_HU_PI_Item_Product_ID
		, e.C_Flatrate_DataEntry_ID
		, e.MonthDate
	;

	--
	--
	--
	raise notice 'Replacing PMM_Balance content with what we calculated';
	delete from PMM_Balance;
	insert into PMM_Balance
	(
		c_bpartner_id
		, m_product_id
		, m_hu_pi_item_product_id
		, C_Flatrate_DataEntry_ID
		--
		, MonthDate
		, WeekDate
		--
		, QtyOrdered
		, QtyOrdered_TU
		, QtyPromised
		, QtyPromised_TU
		, QtyDelivered
		--
		, pmm_balance_id
		, ad_client_id
		, ad_org_id
		, isactive
		, created
		, createdby
		, updated
		, updatedby
	)
	select
		c_bpartner_id
		, m_product_id
		, m_hu_pi_item_product_id
		, C_Flatrate_DataEntry_ID
		--
		, monthdate
		, weekdate
		--
		, qtyordered
		, qtyordered_tu
		, qtypromised
		, qtypromised_tu
		, QtyDelivered
		--
		, pmm_balance_id
		, ad_client_id
		, ad_org_id
		, isactive
		, created
		, createdby
		, updated
		, updatedby
	from TMP_PMM_Balance_Rebuild;
end;
$BODY$
LANGUAGE plpgsql;



-- select de_metas_procurement.PMM_Balance_Rebuild();

