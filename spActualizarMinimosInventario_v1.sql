SET NOCOUNT ON;
--EXEC spActualizarMinimosInventario 30
IF EXISTS (SELECT 1 FROM SYS.objects WHERE NAME ='spActualizarMinimosInventario')
DROP PROC dbo.spActualizarMinimosInventario
GO
CREATE PROCEDURE [dbo].[spActualizarMinimosInventario]
@FDemandaProm		INT 
AS
BEGIN
   DECLARE 
	@FechaA				DATE = DATEADD(DAY, -1, GETDATE()),
    @FechaD				DATE


	SET @FechaD = DATEADD(MONTH, -3, @FechaA)

	IF COALESCE(@FDemandaProm,0) <= 30 
	SET @FDemandaProm = 30


    ;WITH UniversoArticulos AS (SELECT 
        vt.Articulo, 
        vt.Almacen,
        SUM(CASE WHEN vt.Mov IN ('Factura','Factura Com.Ext40') AND vt.Estatus = 'CONCLUIDO' THEN vt.Cantidad ELSE 0 END) AS Demanda90,
        SUM(CASE WHEN mt.Clave = 'VTAS.P' AND mt.SubClave = 'VTAS.PNVK' AND vt.Mov <> 'Cotizacion' AND vt.Estatus = 'PENDIENTE' AND Situacion = 'Autorización de Pedido' AND mt.Mov NOT LIKE 'PS%'
				THEN CASE WHEN vt.Cantidad = VT.CantidadPendiente THEN vt.Cantidad ELSE vt.CantidadPendiente END 
				ELSE 0 END) AS Pedido
	FROM VentaTCalc vt
	JOIN MovTipo	mt	ON vt.Mov=mt.Mov AND Modulo = 'VTAS'
    WHERE vt.Almacen IN ('10','15') 
      AND vt.FechaEmision BETWEEN @FechaD AND @FechaA
    GROUP BY vt.Articulo, vt.Almacen
	),Totales AS (
SELECT 
    a.Almacen,
    a.Articulo,
    d.Descripcion1,
    d.Unidad,
    COALESCE(b.Demanda90, 0) AS DEMANDA90,
    COALESCE(b.Pedido, 0) AS PEDIDO,
    a.Disponible,
    c.Factor
FROM ArtDisponible a                    
LEFT JOIN UniversoArticulos b ON a.Articulo = b.Articulo AND a.Almacen = b.Almacen
JOIN ArtUnidad c ON a.Articulo = c.Articulo
JOIN Art d ON a.Articulo = d.Articulo
WHERE a.Almacen IN ('10','15')
  AND c.Unidad = 'CJA-CAJA'
  AND a.Disponible > 0.00
)

SELECT  Almacen,
		Articulo,
		Descripcion1									AS DDescripcion,
		Unidad,
		ROUND(DEMANDA90,4)								AS Demanda90,
		ROUND((DEMANDA90 / 90),4)						AS DemandaDiaPromedio,
		ROUND((DEMANDA90 * @FDemandaProm),4)			AS DemandaPromedio, --variable
		ROUND(PEDIDO,4)									AS Pedido,
		ROUND(((DEMANDA90 * @FDemandaProm)+PEDIDO),4)	AS Minimo,
		ROUND(Disponible,4)								AS Existencia,
		ROUND((((DEMANDA90 * @FDemandaProm)+PEDIDO) - Disponible),4)		AS Sugerido,
		Factor											AS PzaCaja,
		CASE WHEN (((DEMANDA90 * @FDemandaProm)+PEDIDO) - Disponible) < 0.00 THEN 0 ELSE CEILING ( ((((DEMANDA90 * @FDemandaProm)+PEDIDO) - Disponible) / Factor) / Factor ) END AS SugRedon
		--,
		--@FDemandaProm									AS FACTORDEMANDAPROMEDIO
		
  FROM Totales
  --WHERE Almacen = '15'
 ORDER BY 1,5 DESC
--EXEC spActualizarMinimosInventario 40
END
GO
