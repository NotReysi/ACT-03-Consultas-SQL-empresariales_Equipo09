# Conclusión y Hallazgos de Negocio - LibroMundo

## Hallazgos de Rentabilidad
Al ejecutar el reporte de rentabilidad comparativo entre el primer y segundo trimestre de 2026, logramos identificar diferencias críticas en el desempeño regional. El uso del Top 5 permitió aislar a los "campeones de rentabilidad". Observamos que ciertos productos (especialmente en la categoría de papelería e ítems no editoriales asociados al regreso a clases / temporadas) generaron márgenes altos que superaron con creces su tasa de devoluciones.

La decisión técnica de vincular las devoluciones a la fecha de la **venta original** fue vital. De lo contrario, un producto devuelto en Q2 que se vendió masivamente en Q1 habría distorsionado la rentabilidad real del segundo trimestre, ocultando el verdadero desempeño de ventas de ese periodo.

## Limitaciones del Modelo
Durante la extracción de datos detectamos algunas limitaciones operativas:
1. **Cancelaciones:** Al carecer de un campo "estado" en la tabla `fact_ventas`, no fue posible excluir ventas canceladas previas a la facturación.
2. **Costo de Inventario Recuperado:** Nuestra fórmula de rentabilidad castiga directamente el margen restando el *importe devuelto*, pero no re-suma el costo del ítem si este regresó al inventario en buen estado. Esto hace que nuestra métrica sea conservadora.

## Aprendizajes Técnicos y Uso de IA
La migración de la estructura original (creada en PostgreSQL) hacia MySQL 8.0 nos exigió depurar diferencias de sintaxis importantes, como los campos autonuméricos (`AUTO_INCREMENT` vs `IDENTITY`) y los errores de agrupación estricta (Error 1055). 

El uso de Inteligencia Artificial fue clave como soporte de arquitectura. En lugar de pedirle a la IA "hazme el query", utilizamos prompts estructurados brindando el DDL, el grano del modelo y las reglas de negocio. Esto permitió que la IA estructurara un esqueleto lógico (basado en CTEs y Window Functions) que posteriormente nosotros validamos, iteramos y corregimos (como el JOIN de temporalidad de devoluciones y los índices de optimización recomendados).