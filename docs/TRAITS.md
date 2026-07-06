# Sistema de Niveles de Equipamiento y Sinergias (Estilo TFT)

Este documento detalla el plan técnico para implementar un sistema de progresión y personalización de estadísticas basado en el nivel y los rasgos (*traits*) de los objetos equipados.

## Resumen del Objetivo
Queremos que los objetos de equipamiento tengan un **nivel** (ej. "Casco de Nivel 5") y **rasgos** (ej. "Matón", "Mago"). Al equipar estas piezas en los slots de equipamiento, el nivel del objeto se acumula como puntos para ese rasgo. Si el total acumulado alcanza ciertos umbrales (ej. 2 puntos, 8 puntos), el jugador activa bonificaciones globales en sus estadísticas (vida máxima, regeneración de maná, probabilidad crítica, etc.), de manera similar a las sinergias de Teamfight Tactics.

---

## Revisión de Usuario Requerida

> [!IMPORTANT]
> **Reglas de Cálculo de Puntos de Sinergia:**
> Proponemos que los puntos que una pieza de equipo aporta a un rasgo sean iguales al **nivel del objeto**.
> * *Ejemplo:* Si tienes un Casco Nivel 5 con el rasgo "Matón" y un Escudo Nivel 3 con el rasgo "Matón", tu total acumulado de "Matón" será de **8 puntos** (5 + 3), lo que activaría el umbral de Nivel 8 del rasgo.
> 
> Por favor, confírmanos si este sistema de cálculo (puntos = nivel del item) te parece adecuado o si prefieres otro método (ej. cada pieza suma 1 punto independientemente de su nivel, y el nivel del item solo multiplica la defensa base).

> [!NOTE]
> **Generación de Objetos:**
> Inicialmente, para mantener el MVP simple, los items tendrán rasgos fijos definidos por su tipo (ej. las espadas siempre tendrán el rasgo "Guerrero/Asesino", los cascos de placas tendrán "Matón") pero sus **niveles** se determinarán al momento de ser soltados/comprados.

---

## Preguntas Abiertas

1. **¿Qué rasgos y umbrales iniciales te gustaría tener?**
   Proponemos empezar con tres rasgos básicos para probar el sistema:
   * **Matón (Brawler):** 
     * Umbral 2: +20% Vida Máxima
     * Umbral 8: +50% Vida Máxima
   * **Mago (Mage):**
     * Umbral 2: +25% Regeneración de Maná
     * Umbral 6: +60% Regeneración de Maná
   * **Asesino (Assassin):**
     * Umbral 3: +15% Probabilidad de Crítico
     * Umbral 6: +30% Probabilidad de Crítico y +50% Daño de Crítico

2. **Diseño de la Interfaz (UI):**
   * ¿Dónde preferirías mostrar las sinergias activas? Proponemos añadir una sección vertical en el lateral izquierdo del panel de inventario actual (`InventoryUI.lua`), mostrando los iconos/nombres de los rasgos activos y sus puntos acumulados.

---

## Cambios Propuestos

### 1. Backend & Base de Datos (Fastify + PostgreSQL)

#### [MODIFY] [schema.sql](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/backend/src/schema.sql)
Añadiremos de forma segura e idempotente las nuevas columnas a la tabla de inventario:
```sql
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS item_level INT NOT NULL DEFAULT 1;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS traits JSONB NOT NULL DEFAULT '{}'::jsonb;
```

#### [MODIFY] [inventory.js](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/backend/src/inventory.js)
* Actualizar `fetchRows` para seleccionar `item_level AS "itemLevel"` y `traits`.
* Actualizar `getInventory` para mapear y devolver estos campos al cliente de Roblox.
* Actualizar `addItem` para aceptar parámetros `itemLevel` y `traits` opcionales y guardarlos en la base de datos al insertar.

#### [MODIFY] [inventory.js (routes)](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/backend/src/routes/inventory.js)
* Modificar la ruta `/player/:id/inventory/add` para aceptar `itemLevel` y `traits` en el cuerpo del request.

---

### 2. Roblox Shared & Config

#### [NEW] [SynergyConfig.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/shared/SynergyConfig.lua)
Crear un archivo de configuración para definir las sinergias, umbrales y sus efectos:
```lua
local SynergyConfig = {}

SynergyConfig.Traits = {
	Maton = {
		DisplayName = "Matón",
		Description = "Otorga vida máxima adicional.",
		Thresholds = {
			{ points = 2, buff = { MaxHealthMult = 1.20 } },
			{ points = 8, buff = { MaxHealthMult = 1.50 } },
		}
	},
	Mago = {
		DisplayName = "Mago",
		Description = "Aumenta la regeneración de maná.",
		Thresholds = {
			{ points = 2, buff = { ManaRegenMult = 1.25 } },
			{ points = 6, buff = { ManaRegenMult = 1.60 } },
		}
	},
	Asesino = {
		DisplayName = "Asesino",
		Description = "Aumenta la probabilidad de crítico.",
		Thresholds = {
			{ points = 3, buff = { CritChanceBonus = 0.15 } },
			{ points = 6, buff = { CritChanceBonus = 0.30, CritMultiplierBonus = 0.50 } },
		}
	}
}

return SynergyConfig
```

---

### 3. Roblox Server-Side Services

#### [NEW] [SynergyService.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/server/SynergyService.lua)
Crear un servicio encargado de:
* Escuchar cuando el jugador equipa/desequipa items (cambios en el contenedor `"equipment"`).
* Sumar los puntos de rasgos activos basados en el nivel y rasgos de los items equipados.
* Evaluar y calcular los multiplicadores de estadísticas resultantes.
* Comunicar los multiplicadores a `HealthService`, `ManaService` y `ClassService`.
* Sincronizar las sinergias activas al cliente para su visualización en la UI.

#### [MODIFY] [HealthService.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/server/HealthService.lua)
* Permitir recibir un multiplicador de sinergia de vida máxima (`MaxHealthMult`) y aplicarlo dinámicamente al recalcular la salud máxima del jugador.

#### [MODIFY] [ManaService.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/server/ManaService.lua)
* Aplicar el multiplicador de regeneración de maná (`ManaRegenMult`) en el bucle de regeneración periódica.

#### [MODIFY] [EnemyService.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/server/EnemyService.lua) y [ClassService.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/server/ClassService.lua)
* Aplicar `CritChanceBonus` y `CritMultiplierBonus` en el cálculo de daño de ataques del jugador.

---

### 4. Roblox Client-Side UI

#### [MODIFY] [InventoryUI.lua](file:///C:/Users/banan/Desktop/wachinadas/FAMANA/roblox/src/client/InventoryUI.lua)
* Mostrar el nivel del objeto y sus rasgos en el tooltip al pasar el cursor sobre las armas/armaduras.
* Diseñar un panel lateral izquierdo que liste las sinergias activas y su nivel actual de activación.

---

## Plan de Verificación

### Pruebas Automatizadas
* **Backend:** Ejecutar pruebas HTTP sobre `/player/:id/inventory/add` enviando `itemLevel` y `traits` y comprobar que se guarden e indexen correctamente.
* **Servidor de Roblox:** Ejecutar tests unitarios sobre `SynergyService` para simular la equipación de items (ej. Casco Nivel 5 Matón, Pechera Nivel 3 Matón) y validar que se calculen exactamente 8 puntos y se apliquen los buffs correspondientes.

### Verificación Manual
1. Equipar un "Casco de Matón Nivel 2" y verificar que la vida máxima del personaje suba de `100` a `120`.
2. Equipar otra pieza de Matón hasta sumar 8 puntos y verificar que la vida suba a `150`.
3. Abrir la interfaz de inventario y comprobar que la barra de sinergias del lado izquierdo muestre correctamente los rasgos activos y sus umbrales.