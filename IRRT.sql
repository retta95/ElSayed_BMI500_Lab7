-- The typical range for serum creatinine is:
-- For adult men, 0.74 to 1.35 mg/dL (65.4 to 119.3 micromoles/L) 
-- For adult women,0.59 to 1.04 mg/dL (52.2 to 91.9 micromoles/L)
-- Serum Creatinine measurnments usually determined using blood or urine sample were found in 
-- select * FROM public.d_labelitems
-- WHERE label in ('Creatinine, Serum','Estimated GFR (MDRD equation)','Total Collection Time','Length of Urine Collection'); 

-- Creatinine, Serum  row_id=281, itemide=51081
-- Estimated GFR (MDRD equation)  row_id=121, itemid=50920

-- From MIMIC III table infoermation Labelitem are linked to labevents: 
-- SELECT * FROM public.labevents
-- WHERE itemid in ('51081','50920');

-- From MIMIC III table info labevents are linked to PATIENTS on SUBJECT_ID and ADMISSIONS on HADM_ID

-- To know the initiation of RRT-> Procedureevents_MV CRRT Filter Change
-- SELECT * FROM public.procedureevents_mv
-- WHERE ORDERCATEGORYNAME in ('CRRT Filter Change','Dialysis');
-- itemid= 225802 for dialysis and 225436 for CRRT 
-- I need to make a table the has SUBJECT_ID, HADM_ID,itemide, age, gender, Scr value, RRT, eGFR in patients <18 years old, urine output amount, urine time length: 
-- URINE OUTPUT: ml/kg/h for 6-12 hours:
-- To predict the baseline creatinine value, three estimation methods were tested: Firstly, (‘MDRD-based estimation method’) we solved the MDRD formula for GFR 75 ml/min/1.73 m2 as suggested by ADQI:
-- Serumcreatinine=(75/[186×(age^−0.203)×(0.742if female)×(1.21 if black)]^−0.887.
WITH patient_age (ID, fadmit, age) AS
(
select g.SUBJECT_ID, min(ad.admittime) as fadmit, min(ROUND((cast(ad.admittime as date) - cast(c.dob as date))/365.242, 2)) AS age
	FROM public.d_labelitems a
	INNER JOIN public.labevents g
	on a.itemid=g.itemid
	AND a.label in ('Creatinine, Serum')
	-- AND a.label in ('Creatinine, Serum','Estimated GFR (MDRD equation)','Total Collection Time','Length of Urine Collection')
	INNER JOIN public.patients c
	on g.SUBJECT_ID=c.SUBJECT_ID
	INNER JOIN public.admission ad
	on ad.SUBJECT_ID=c.SUBJECT_ID
	Group by g.subject_ID, ad.admittime, c.dob
),
NTable (
HADM_ID, itemid,fadmit, ID, gender, ethnicity,age, labell, Scr, Unites, urineoutput, baseline) AS (
select g.HADM_ID, a.itemid, fadmit, ID, c.gender,ad.ethnicity, age, a.label, g.valuenum, g.valueuom, uo.value,
case 
	when c.gender='F' and ad.ethnicity='BLACK/AFRICAN AMERICAN'
	then (75/(186*(power(age,(-0.203))*(0.742)*(power(1.21,-0.887)))))
	when c.gender='M' and ad.ethnicity='BLACK/AFRICAN AMERICAN'
	then (75/(186*(power(age,(-0.203))*(power(1.21,-0.887)))))
	when c.gender='F' and ad.ethnicity!='BLACK/AFRICAN AMERICAN'
	then (75/(186*(power(age,(-0.203))*(0.742))))
	when c.gender='M' and ad.ethnicity!='BLACK/AFRICAN AMERICAN'
	then (75/(186*(power(age,(-0.203)))))
	end as scr_baseline,
case
	when pro.ORDERCATEGORYNAME = 'CRRT Filter Change'
	then '1'
	else '0'
	end as IRRT
	
FROM patient_age
	INNER JOIN public.labevents g
	on ID=g.SUBJECT_ID
	INNER JOIN public.d_labelitems a
	on a.itemid=g.itemid
	AND a.label in ('Creatinine, Serum')
	-- AND a.label in ('Creatinine, Serum','Estimated GFR (MDRD equation)','Total Collection Time','Length of Urine Collection')
	INNER JOIN public.patients c
	on ID=c.SUBJECT_ID
	INNER JOIN public.admission ad
	on ID=ad.SUBJECT_ID
	INNER JOIN public.procedureevents_mv pro
	on ID=pro.SUBJECT_ID
	INNER JOIN public.urineoutput uo
	on ID=uo.SUBJECT_ID
)
select distinct HADM_ID, itemid, ID, gender, age, Scr, baseline, urineoutput, IRRT,
case
when (NTable.Scr/NTable.baseline>=1.5 and NTable.Scr/NTable.baseline<2) and IRRT='0'
then '1'
when (NTable.Scr/NTable.baseline>=2 and NTable.Scr/NTable.baseline<3) and IRRT='0'
then '2'
when (NTable.Scr/NTable.baseline>=3) or IRRT='1'
then '3'
else '0'
end as AKI_Stage
from NTable
order by ID