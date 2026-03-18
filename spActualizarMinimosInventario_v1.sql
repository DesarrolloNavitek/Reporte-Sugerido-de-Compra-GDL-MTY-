SET NOCOUNT ON;
--EXEC spActualizarMinimosInventario 30
IF EXISTS (SELECT 1 FROM SYS.objects WHERE NAME ='spActualizarMinimosInventario')
DROP PROC dbo.spActualizarMinimosInventario
GO
CREATE PROCEDURE [dbo].[spActualizarMinimosInventario]
@Almacen			VARCHAR(10),
@FDemandaProm		INT

AS
BEGIN
   DECLARE 
	@FechaA				DATE = DATEADD(DAY, -1, GETDATE()),
    @FechaD				DATE

	--obtenemos los 3 meses posteriores a la fecha actual
	SET @FechaD = DATEADD(MONTH, -3, @FechaA)
	-- tiempo minimo para ejecutar el reporte
	SET @FDemandaProm = CASE WHEN @FDemandaProm < 30 THEN 30 ELSE @FDemandaProm END
	

	-- Se obtienen todos los registros de facturas y pedidos
    ;WITH UniversoArticulos AS (SELECT 
        vt.Articulo, 
        vt.Almacen,
        SUM(CASE WHEN vt.Mov IN ('Factura','Factura Com.Ext40') AND vt.Estatus = 'CONCLUIDO' THEN vt.Cantidad ELSE 0 END) AS Demanda90,
        SUM(CASE WHEN mt.Clave = 'VTAS.P' AND mt.SubClave = 'VTAS.PNVK' AND vt.Mov <> 'Cotizacion' AND vt.Estatus = 'PENDIENTE' AND Situacion = 'Autorización de Pedido' AND mt.Mov NOT LIKE 'PS%'
				THEN CASE WHEN vt.Cantidad = VT.CantidadPendiente THEN vt.Cantidad ELSE vt.CantidadPendiente END 
				ELSE 0 END) AS Pedido
	FROM VentaTCalc vt
	JOIN MovTipo	mt	ON vt.Mov=mt.Mov AND Modulo = 'VTAS'
    WHERE vt.Almacen = @Almacen--IN ('10','15') 
      AND vt.FechaEmision BETWEEN @FechaD AND @FechaA
    GROUP BY vt.Articulo, vt.Almacen
	),Totales AS (
	-- Obtenemos la existencia de los almacenes 10 y 15 de los productos terminados
SELECT 
    a.Almacen,
    a.Articulo,
    d.Descripcion1,
    d.Unidad,
    ROUND(COALESCE(b.Demanda90, 0),4)	AS DEMANDA90,
    ROUND(COALESCE(b.Pedido, 0),4)		AS PEDIDO,
    ROUND(Disponible,4)					AS Disponible,
    c.Factor
FROM ArtDisponible a                    
LEFT JOIN UniversoArticulos b ON a.Articulo = b.Articulo AND a.Almacen = b.Almacen
JOIN ArtUnidad c ON a.Articulo = c.Articulo
JOIN Art d ON a.Articulo = d.Articulo
WHERE a.Almacen = @Almacen --IN ('10','15')
  AND c.Unidad = 'CJA-CAJA'
  AND d.Linea = '1-PT'
  AND a.Disponible > 0.0000
), DemandaDiaPromedio AS (
--Calcula la demanda promedio por día
SELECT  Almacen,
		Articulo,
		(COALESCE(Demanda90, 0) / 90)	AS DemandaDiaPromedio
		
  FROM Totales
), DemandaPromedio AS (
--Calcula la demanda promedio
SELECT b.Almacen,
		b.Articulo,
		(DemandaDiaPromedio * @FDemandaProm) AS DemandaPromedio
FROM DemandaDiaPromedio  a
JOIN Totales		b ON a.Articulo = b.Articulo AND a.Almacen = b.Almacen

), Minimo AS (
--Minimo: DemandaPromedio + Pedidos
SELECT b.Almacen,
		b.Articulo,
		a.DemandaPromedio + Pedido   AS Minimo
  FROM DemandaPromedio		a
  JOIN Totales		b ON a.Articulo=b.Articulo AND a.Almacen=b.Almacen
), Sugerido AS (
--Sugerido: Minimo - Existencia
SELECT b.Almacen,
		b.Articulo,
		Minimo - Disponible   AS Sugerido
  FROM Minimo		a
  JOIN Totales		b ON a.Articulo=b.Articulo AND a.Almacen=b.Almacen
), SugRedon AS(
--SugRedon: Dividir el sugertido entre el contenido de la caja, esto da las cajas a pedir, aplicar CEILING para redondear hacia arriba el total de cajas
-- multiplicar el total de cajas * el contenido de cada una y se obtiene el total en piezas para cajas completas
--CASE WHEN (((DEMANDA90 * @FDemandaProm)+PEDIDO) - Disponible) < 0.00 THEN 0 ELSE CEILING ( ((((DEMANDA90 * @FDemandaProm)+PEDIDO) - Disponible) / Factor) * Factor ) END
SELECT b.Almacen,
		b.Articulo,
		--En caso de que el sugerido sea negativo no se muestran datos
		CASE WHEN Sugerido < 0.00 THEN 0 ELSE (CEILING((Sugerido / Factor)) * Factor) END AS SugRedon
  FROM Sugerido 		a
  JOIN Totales		b ON a.Articulo=b.Articulo AND a.Almacen=b.Almacen
)

SELECT a.Almacen,
		a.Articulo,
		Descripcion1,
		Unidad,
		a.Demanda90,
		ROUND(DemandaDiaPromedio,4)			AS DemandaDiaPromedio,
		ROUND(DemandaPromedio,4)			AS DemandaPromedio,
		Pedido,
		ROUND(Minimo,4)						AS CantidadMinima,
		Disponible AS Existencia,
		ROUND(Sugerido,4)					AS Sugerido,
		Factor								AS PzaCaja,
		SugRedon,
		@FDemandaProm						AS PDemandaPromedio,
		@FechaD								AS FechaD,
		@FechaA								AS FechaA
  FROM Totales		a
  JOIN DemandaDiaPromedio  b		ON a.Articulo=b.Articulo AND a.Almacen=b.Almacen
  JOIN DemandaPromedio		c	ON a.Articulo=c.Articulo AND a.Almacen=c.Almacen
  JOIN Minimo				d	ON a.Articulo=d.Articulo AND a.Almacen=d.Almacen
  JOIN Sugerido				e	ON a.Articulo=e.Articulo AND a.Almacen=e.Almacen
  JOIN SugRedon				f	ON a.Articulo=f.Articulo AND a.Almacen=f.Almacen
  GROUP BY a.Almacen,		
		a.Articulo,
		Descripcion1,
		Unidad,
		a.Demanda90,
		DemandaDiaPromedio,
		DemandaPromedio,
		Pedido,
		Minimo,
		Disponible,
		Sugerido,
		Factor,
		SugRedon
ORDER BY 1,5 DESC
--EXEC spActualizarMinimosInventario 30,'15'
END
