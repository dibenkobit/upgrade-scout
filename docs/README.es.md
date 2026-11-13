# Upgrade Scout

<img src="logo/logo.png" alt="Logotipo de Upgrade Scout" width="128" align="right">

**Encuentra en la casa de subastas equipo mejor que el tuyo y que puedes pagar.** Un addon para World of Warcraft Forever.

**[Descargar en CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · Español · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Abre la casa de subastas, haz clic en la pestaña **Mejoras** y pulsa **Escanear**. Verás una lista
de equipo mejor que el que llevas, ranura por ranura, con sus precios. Pulsa **Comprar** en el
objeto que quieras.

## Qué hace

- Puntúa el equipo con [Pawn](https://www.curseforge.com/wow/addons/pawn), así que la lista coincide con las
  flechas verdes de Pawn.
- Muestra solo lo que puedes equipar ahora mismo y pagar.
- Marca dos objetos en cada ranura. **Mayor mejora** es el más fuerte. **Más rentable** es el más
  barato por punto de mejora.
- **Mejor conjunto por** elige las mejoras que, juntas, dan más por tu oro o por una suma que
  escribas.
- La pestaña **Consumibles** muestra pociones, elixires, comida y vendas que puedes usar. Primero,
  lo más útil para tu personaje.
- Las dos pestañas sirven también para tus otros personajes.

Cualquier clase, cualquier nivel. Inglés, chino (simplificado y tradicional), alemán, ruso,
francés, español, portugués de Brasil y coreano.

## Instalación

**[Instalar desde CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)**

La aplicación de CurseForge lo hace todo por ti, Pawn incluido.

Necesitas World of Warcraft Forever (1.60.1) y [Pawn](https://www.curseforge.com/wow/addons/pawn).
Sin Pawn el addon no se carga.

A mano:

1. Descarga `UpgradeScout-<versión>-forever.zip` de [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout)
   o de las [versiones en GitHub](https://github.com/dibenkobit/upgrade-scout/releases).
2. Descomprímelo en `World of Warcraft\_forever_\Interface\AddOns`.
3. Reinicia el juego.

## Conviene saber

- Los precios son de compra inmediata. Las subastas que solo admiten pujas se omiten.
- **Top 5 por ranura** mantiene la lista corta. Desactívalo para ver todas las mejoras. El escaneo
  tarda entonces más, hasta unos minutos en una casa de subastas con mucho movimiento.
- Un `*` amarillo tras el nombre: el objeto tiene efectos que Pawn no sabe puntuar.
- Las pociones de salud y de maná no tienen puntuación: Pawn no tiene un número para «restaura
  700 p. de salud».
- Unas botas «del tigre» y unas botas «de la ballena» son objetos distintos con precios distintos.
  La pestaña «Vender» del juego los muestra todos en una sola lista, así que el precio más bajo de
  allí puede ser de otro objeto.

## Comprar para otro personaje

1. Entra una vez con el otro personaje con el addon instalado. El addon guarda su equipo, su nivel
   y sus habilidades.
2. Con el personaje que está en la casa de subastas, elige la escala del otro personaje en la lista
   **Escala de Pawn** y pulsa **Escanear**.

Ahora la lista es para ese personaje. Sigue pagando el personaje con el que juegas.

En un buzón, saca del correo el equipo que compraste. Un botón bajo la ventana del correo lo mete
entonces en una carta para ese personaje. Revisa la carta y pulsa **Enviar**. Los consumibles los
envías tú.

El addon conoce al otro personaje tal como era la última vez que jugaste con él. Vuelve a entrar
con él cuando suba de nivel o cambie de equipo.

## Comandos

- `/upscout` abre la pestaña «Mejoras». La casa de subastas debe estar abierta.
- `/upscout stats` muestra cuánto tardó el último escaneo.
- `/upscout forget Nombre` quita de la lista un personaje borrado.

## Desarrollo

Las pruebas y la publicación de versiones se explican en la [versión en inglés](../README.md#development).

## Licencia

Todos los derechos reservados, consulta [LICENSE](../LICENSE). Pawn es un addon aparte, de Vger, y
no está incluido.
