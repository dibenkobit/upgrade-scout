# Upgrade Scout

<img src="logo/logo.png" alt="Logotipo de Upgrade Scout" width="128" align="right">

**Encuentra en la casa de subastas las mejoras de equipo y los consumibles que puedes usar y pagar.** Un addon para World of Warcraft Forever.

**Descargar en [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) o [Wago](https://addons.wago.io/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · Español · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Abre la casa de subastas, haz clic en la pestaña **Mejoras** y pulsa **Escanear**. Verás una lista
de equipo mejor que el que llevas, ranura por ranura, con sus precios. Pulsa **Comprar** en el
objeto que quieras.

La pestaña **Consumibles** hace lo mismo con pociones, elixires, frascos, comida, vendas y aceites.
Muestra los que tu personaje puede usar y puntúa lo que aporta cada uno. **Lo mejor para mí** deja
uno de cada tipo: el que más te aporta, a su precio más bajo.

Fuera de la casa de subastas, la descripción emergente de cualquier objeto muestra cuánto mejor es
que lo que llevas: en tus bolsas, en el botín, en una recompensa de misión y en un enlace del chat.

## Qué hace

- El escaneo muestra solo lo que puedes equipar ahora mismo y pagar.
- La pestaña **Consumibles** muestra pociones, elixires, frascos, comida, vendas y aceites que
  puedes usar. Primero, lo más útil para tu personaje. Lo que no te sirve se omite.
- Marca dos objetos en cada ranura. **Mayor mejora** es el más fuerte. **Más rentable** es el más
  barato por punto de mejora.
- **Precio neto** muestra lo que un objeto te cuesta al final: la compra inmediata menos lo que un
  mercader te paga por él cuando ya no lo necesites. Comprado por 4 de plata y vendido por 3, te
  costó 1.
- **Mejor conjunto por** elige las mejoras que, juntas, dan más por tu oro o por una suma que
  escribas.
- Compra también para tus otros personajes. Un botón en el buzón mete el equipo que compraste en
  una carta para ellos.
- La descripción emergente de cualquier objeto muestra cuánto mejor es que lo que llevas, para
  cada rama de talentos de tu clase, como Armas, Furia y Protección para un guerrero. En la
  ventana del addon puedes dejar una sola línea, la de tu rama, y elegir dónde se muestran: en
  las pestañas del addon en la casa de subastas, en el resto del juego o en ningún sitio.
- Una flecha verde en el icono de un objeto de tus bolsas o del banco indica una mejora que
  puedes equiparte ahora mismo. Una gris: una mejora en cuanto alcances su nivel.
- Funciona en cuanto lo instalas. La lista **Perfil** empieza en la rama de talentos donde tienes
  más puntos.
- La primera vez que entras, una ventana muestra lo que hace el addon. Ahí puedes desactivar las
  líneas de la descripción y las flechas de las bolsas. El botón del addon junto al minimapa la
  abre de nuevo.
- Puntúa el equipo con pesos propios para cada rama de talentos, calculados con el simulador
  [wowsims/forever](https://github.com/wowsims/forever). No hace falta ningún otro addon.

Cualquier clase, cualquier nivel. Inglés, chino (simplificado y tradicional), alemán, ruso,
francés, español, portugués de Brasil y coreano.

## Instalación

**Instalar desde [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) o [Wago](https://addons.wago.io/addons/upgrade-scout)**

La aplicación de CurseForge o de Wago lo hace todo por ti.

Necesitas World of Warcraft Forever (1.60.1). No hace falta ningún otro addon.

A mano:

1. Descarga `UpgradeScout-<versión>-forever.zip` de [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout), [Wago](https://addons.wago.io/addons/upgrade-scout)
   o de las [versiones en GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Descomprímelo en `World of Warcraft\_forever_\Interface\AddOns`.
3. Reinicia el juego.

## Conviene saber

- La puntuación de un objeto es la suma de sus estadísticas, cada una por su peso en el perfil. El
  perfil se elige en la lista **Perfil**; al principio tiene la rama de talentos donde tienes más
  puntos. Puedes elegir otra.
- Los pesos están calculados para un personaje de nivel 60, así que son una aproximación. Por
  debajo del nivel 60, el golpe, el crítico, la celeridad y la pericia valen menos, según
  simulaciones de personajes subiendo de nivel.
- El aguante (salvo en los tanques) y, en los sanadores, el intelecto, el espíritu y la regeneración de maná se fijan a mano: una simulación de daño no muestra cuánto cuesta seguir con vida o quedarse sin maná.
- La armadura, el valor de bloqueo, la defensa, la esquiva y la parada cuentan en cada perfil: frente al aguante, tanto como le sirven al tanque del simulador.
- Un `~` tras el nombre de un perfil significa que esa rama aún no tiene
  simulación y sus pesos son estimados.
- Los precios son de compra inmediata. Las subastas que solo admiten pujas se omiten.
- Con **Precio neto** marcado, la columna de precios y **Más rentable** van por el precio neto. Lo
  que puedes pagar y **Mejor conjunto por** siguen yendo por la compra inmediata: es lo que pagas.
- **Top 5 por ranura** mantiene la lista corta. Desactívalo para ver todas las mejoras. El escaneo
  tarda entonces más, hasta unos minutos en una casa de subastas con mucho movimiento.
- **Mejora** dice cuánto mejor es un objeto que el que reemplaza, en porcentaje. **Nuevo**
  significa que la ranura está vacía. Los puntos, como `+6 pts`, significan que lo que llevas ahí
  no aporta nada a tu perfil.
- Un `*` amarillo tras el nombre: el objeto tiene efectos que la puntuación no cuenta.
- Las pociones de salud y de maná no tienen puntuación: ningún peso pone número a «restaura
  700 p. de salud».
- Unas botas «del tigre» y unas botas «de la ballena» son objetos distintos con precios distintos.
  La pestaña «Vender» del juego los muestra todos en una sola lista, así que el precio más bajo de
  allí puede ser de otro objeto.

## Comprar para otro personaje

1. Entra una vez con el otro personaje con el addon instalado. El addon guarda su equipo, su nivel
   y sus habilidades.
2. Con el personaje que está en la casa de subastas, elige el perfil del otro personaje en la lista
   **Perfil** y pulsa **Escanear**.

Ahora la lista es para ese personaje. Sigue pagando el personaje con el que juegas.

En un buzón, saca del correo el equipo que compraste. Un botón bajo la ventana del correo lo mete
entonces en una carta para ese personaje. Revisa la carta y pulsa **Enviar**. Los consumibles los
envías tú.

El addon conoce al otro personaje tal como era la última vez que jugaste con él. Vuelve a entrar
con él cuando suba de nivel o cambie de equipo.

## Comandos

- `/upscout` abre la ventana del addon: lo que hace y sus ajustes. En la casa de subastas abre la
  pestaña «Mejoras».
- `/upscout stats` muestra cuánto tardó el último escaneo.
- `/upscout stats` y un objeto (Mayús-clic para ponerlo en la línea de chat) muestra cada
  estadística del objeto, su peso en el perfil y lo que suman.
- `/upscout forget Nombre` quita de la lista un personaje borrado.

## Desarrollo

Las pruebas y la publicación de versiones se explican en la [versión en inglés](DEVELOPMENT.md).

## Licencia

Todos los derechos reservados, consulta [LICENSE](../LICENSE). Los pesos se calcularon con
[wowsims/forever](https://github.com/wowsims/forever), y su parte por debajo del nivel 60 con [MythicSim](https://github.com/sage3648/mythicsim-forever-engine).
Ambos tienen licencia MIT.
