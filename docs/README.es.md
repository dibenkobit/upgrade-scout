# Upgrade Scout

<img src="logo/logo.png" alt="Logotipo de Upgrade Scout" width="128" align="right">

**Encuentra en la casa de subastas las mejoras de equipo y los consumibles que puedes usar y pagar.** Un addon para World of Warcraft Forever.

**Descargar en [CurseForge](https://www.curseforge.com/wow/addons/upgrade-scout) o [Wago](https://addons.wago.io/addons/upgrade-scout)**

[English](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [Deutsch](README.de.md) · [Русский](README.ru.md) · [Français](README.fr.md) · Español · [Português](README.pt-BR.md) · [한국어](README.ko.md)

Abre la casa de subastas, haz clic en la pestaña **Mejoras** y pulsa **Escanear**. Verás una lista
de equipo mejor que el que llevas, ranura por ranura, con sus precios. Pulsa **Comprar** en el
objeto que quieras.

La pestaña **Consumibles** hace lo mismo con pociones, elixires, frascos, comida, vendas y aceites.
Muestra los que aportan algo a tu personaje y puntúa lo que aporta cada uno. **Lo mejor para mí**
deja uno de cada tipo: el que más te aporta, a su precio más bajo. **Todo lo que puedo usar** añade
lo que no tiene puntuación: comida y bebida corrientes, pociones de salud y de maná, vendas.

Fuera de la casa de subastas, la descripción emergente de cualquier objeto muestra cuánto mejor es
que lo que llevas: en tus bolsas, en el botín, en una recompensa de misión y en un enlace del chat.

## Qué hace

- El escaneo muestra solo lo que puedes equipar ahora mismo y pagar.
- La pestaña **Consumibles** muestra las pociones, elixires, frascos, comida y aceites que aportan
  algo a tu personaje. Primero, lo más útil. **Todo lo que puedo usar**, en el menú **Filtros**,
  añade lo que no tiene puntuación: comida y bebida corrientes, pociones de salud y de maná, vendas.
- Marca dos objetos en cada ranura. **Mayor mejora** es el más fuerte. **Más rentable** es el más
  barato por punto de mejora.
- Cada fila tiene dos precios: la **Compra** y el **Precio neto**, lo que un objeto te cuesta al
  final: la compra inmediata menos lo que un mercader te paga por él cuando ya no lo necesites.
  Comprado por 4 de plata y vendido por 3, te costó 1.
- **Mejor conjunto por** elige las mejoras que, juntas, dan más por tu oro o por una suma que
  escribas.
- El menú **Filtros** acota la lista. **Mejor tipo de armadura de la clase** omite las armaduras
  más ligeras que la más pesada que lleva tu personaje. **Mejora de al menos** omite las mejoras
  menores que el porcentaje que escribas. **Compra hasta** omite los objetos que cuestan más
  que la suma que escribas: la **Mayor mejora** de cada ranura es entonces la mayor por ese
  precio. **Equipo de como mucho 10 niveles por debajo** omite el equipo hecho para niveles muy
  por debajo del de tu personaje, y el escaneo es más corto. **Armas** dice cómo ocupa las manos
  tu personaje, con un arma de dos manos o con un arma de una mano y un escudo, y qué tipos de
  arma se le ofrecen.
- Compra también para tus otros personajes. Un botón en el buzón mete el equipo que compraste en
  una carta para ellos.
- La descripción emergente de cualquier objeto muestra cuánto mejor es que lo que llevas, para
  cada rama de talentos de tu clase, como Armas, Furia y Protección para un guerrero. En la
  ventana del addon puedes dejar una sola línea, la de tu rama, y elegir dónde se muestran: en
  las pestañas del addon en la casa de subastas, en el resto del juego o en ningún sitio.
- Una flecha verde en el icono de un objeto de tus bolsas o del banco indica una mejora que
  puedes equiparte ahora mismo. Una gris: una mejora en cuanto alcances su nivel. Las flechas se
  muestran también en las ventanas de bolsas y de banco de EllesmereUI.
- Funciona en cuanto lo instalas. La lista **Perfil** empieza en la rama de talentos donde tienes
  más puntos.
- La primera vez que entras, una ventana muestra lo que hace el addon. Ahí puedes desactivar las
  líneas de la descripción y las flechas de las bolsas. El botón del addon junto al minimapa la
  abre de nuevo.
- Puntúa el equipo con pesos propios para cada rama de talentos, calculados con el simulador
  [wowsims/forever](https://github.com/wowsims/forever). No hace falta ningún otro addon.
- ¿Usas Pawn? Elige **Pawn** en la ventana del addon y el equipo se puntúa con tus escalas de Pawn,
  no con los pesos del addon. Las listas y las flechas de las bolsas se guían por ellas, y las líneas
  de la descripción son las de Pawn.
- ¿Usas Forever Companion? Elige **Forever Companion** ahí mismo y el equipo se puntúa con sus
  escalas. Las listas se guían por ellas, y la línea de la descripción y las flechas de las bolsas
  son las de Forever Companion.
- ¿Usas Forever Leveling BiS? Elige **Forever Leveling BiS** ahí mismo y el equipo se puntúa como
  lo puntúa él, para la especialización principal que elegiste en él. Las líneas de la descripción
  y las flechas de las bolsas son las de Forever Leveling BiS.
- ¿Usas GearQuest? Elige **GearQuest** ahí mismo y el equipo se puntúa como lo puntúa él: un
  objeto de sus listas recibe su propia puntuación, y cualquier otro se puntúa con sus pesos.
  Las listas y las flechas de las bolsas se guían por ellos, y para los objetos de sus listas la
  línea de la descripción es la de GearQuest.

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
- La lista aparece antes de comprobar los precios. Hasta que se comprueba un objeto, su precio
  es el más bajo entre sus subastas y puede resultar ser una puja. Puedes comprar enseguida: el
  precio se comprueba antes de cada compra.
- Con **Rentabilidad por precio neto** marcado, **Más rentable** va por el precio neto y no por la
  compra inmediata. Lo que puedes pagar y **Mejor conjunto por** siguen yendo por la compra
  inmediata: es lo que pagas.
- **Top 5 por ranura** deja las cinco mayores mejoras de cada ranura, y además el **Más
  rentable** cuando no está entre ellas. Puedes escribir otro número en lugar del 5, del 1 al
  99. Desactívalo para ver todas las mejoras. Comprobar todos sus precios tarda entonces más,
  hasta unos minutos en una casa de subastas con mucho movimiento.
- **Ocultar ofertas peores**, justo debajo, está desactivado hasta que lo marques. Omite un
  objeto cuando otro más fuerte cuesta lo mismo o menos por punto. Lo que queda va de la
  **Mayor mejora** hacia abajo, cada fila más barata por punto que la de encima. Si **Top 5
  por ranura** también está marcado, sus mayores mejoras se toman de lo que queda. Con esta
  casilla marcada se comprueban menos precios después de aparecer la lista.
- **Mejora** dice cuánto mejor es un objeto que el que reemplaza, en porcentaje. **Nuevo**
  significa que la ranura está vacía. Los puntos, como `+6 pts`, significan que lo que llevas ahí
  no aporta nada a tu perfil.
- **Mejor tipo de armadura de la clase** conserva la armadura más pesada que tu personaje ha
  aprendido a llevar: cuero para un cazador, mallas cuando las haya aprendido. Capas, anillos,
  armas y escudos se quedan en la lista. Un mago, un sacerdote y un brujo solo llevan tela y no
  tienen esta casilla.
- **Mejora de al menos** va por el porcentaje de la columna **Mejora**. Un objeto para una ranura
  vacía se queda siempre.
- **Compra hasta** es lo máximo que se paga por un solo objeto. **Mejor conjunto por** tiene su
  propio presupuesto y no la usa.
- **Equipo de como mucho 10 niveles por debajo** está desactivado hasta que lo marques. Omite el
  equipo hecho para un nivel que quede más que ese número por debajo del de tu personaje.
  Puedes escribir otro número, del 1 al 59. Un escaneo con este filtro también se salta ese
  equipo, así que es más corto: cuanto más alto es tu nivel, más ahorra. El equipo que no pide
  nivel no se toca: aparece en la lista si es una mejora. Si subes el número o quitas la marca
  después de un escaneo, vuelve a escanear: la línea de estado dice desde qué nivel leyó el
  último. Las flechas de las bolsas no se guían por este filtro.
- **Armas** abre un menú propio. **Cualquiera** ofrece armas de una mano y de dos manos por
  igual. **Dos manos** omite las armas de una mano, los escudos y los objetos de mano izquierda.
  **Una mano, escudo y mano izquierda** omite las armas de dos manos. Debajo hay una casilla por
  cada tipo de arma que tu clase puede usar: sin marcar, las armas de ese tipo se omiten. Las
  flechas de las bolsas también se guían por todo esto.
- Cada perfil de un personaje tiene su propia elección y sus propias casillas en **Armas**: un
  guerrero puede llevar armas de dos manos en Furia y un escudo en Protección. El menú lleva
  por título el perfil que muestra, por ejemplo **Perfil: Protección**.
- Un tipo de arma que tu personaje no ha aprendido lleva **(habilidad no aprendida)** tras su
  nombre y está sin marcar hasta que lo marques. Marcado, sus armas aparecen en la lista
  igualmente, salvo que otra cosa impida a tu personaje usarlas, como el nivel que piden. La
  descripción emergente de la fila dice que hay que aprender la habilidad. **Mejor conjunto
  por** no toma ninguna.
- Un guerrero o un paladín con el perfil **Protección** empieza en **Una mano, escudo y mano
  izquierda** mientras puntúan los pesos del addon: son los de un tanque con escudo. Elige
  **Cualquiera** para ver también las armas de dos manos.
- Con **Una mano, escudo y mano izquierda** elegido, a un personaje que lleva un arma de dos
  manos se le ofrecen armas de una mano, escudos y objetos de mano izquierda como **Nuevo**:
  cada uno cuenta por lo que vale por sí solo, no frente al arma de dos manos. Cuando puntúa
  Forever Leveling BiS, un arma se sigue comparando con el arma de dos manos.
- Cada personaje tiene su propia casilla **Mejor tipo de armadura de la clase**, su propio
  número en **Mejora de al menos**, su propia suma en **Compra hasta**, y su propia casilla y
  su propio número en **Equipo de como mucho 10 niveles por debajo**. Las elecciones en
  **Armas** se guardan para cada uno de sus perfiles. Cuando compras para otro personaje, ves
  y cambias los suyos.
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
