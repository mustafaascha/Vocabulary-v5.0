OPTIONS (errors=0, direct=true)
LOAD DATA 
CHARACTERSET UTF8 LENGTH SEMANTICS CHAR
INFILE 'CMS32_DESC_SHORT_DX.txt'
BADFILE 'CMS_DESC_SHORT_DX.bad'
DISCARDFILE 'CMS_DESC_SHORT_DX.dsc'
TRUNCATE
INTO TABLE CMS_DESC_SHORT_DX
(
	CODE position(1:6), 
	NAME position(7:263) 
)