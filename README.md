# Validátor/opravátor výkresů dle metodiky ČEZ (ČEZ_ST_0093)

Nástroj pro AutoCAD (AutoLISP), který zkontroluje, případně automaticky opraví,
výkres dle metodiky **ČEZ, a. s. – Požadavky na projektovou dokumentaci pro
dodavatele JE (ETE/EDU)**, konkrétně:

- **ČEZ_ST_0093r06** – "Požadavky na projektovou a související dokumentaci"
  (hlavní standard, kap. 3.1 – značení dokumentů, popisové pole, dodavatelské
  číslo, metadata)
- **Volná příloha C – "Požadavky na výkres"** (plný text, poskytnutý
  uživatelem) – konkrétní pravidla pro formu výkresu: kódová stránka,
  zákaz hladiny "0", zákaz XREF/proxy grafiky, barvy čar, typy čar, písmo
  (zakázaný styl STANDARD, povolené výšky), kótování, revize, značení
  projektových pozic, obsah CAD bloků popisového pole
- **Knihovna AutoCAD DJE** – jejich obsah (hladiny, čárové typy, textové
  styly, formáty papíru, blok popisového pole) je navíc zakódovaný přímo
  v oficiální šabloně `CEZ_Sablona vykresu podla VPC_REV2.dwt`

## Co je součástí

| Soubor | Účel |
|---|---|
| `CEZ_ST0093_Validator.lsp` | Hlavní nástroj – příkazy `CEZ-KONTROLA` a `CEZ-OPRAVA` |
| `CEZ_LAYERS_DATA.lsp` | Datová tabulka 457 hladin, 282 čárových typů a 12 textových stylů extrahovaná přímo z oficiální šablony ČEZ |
| `reference/` | Zdrojové dokumenty ČEZ, ze kterých nástroj vychází (standard, návod, šablona, .lin/.ctb soubory) – pro dohledání kontextu, nejsou pro provoz nástroje potřeba |

## Co nástroj kontroluje

1. **Hladiny (layers)** – název, barva (ACI) a čárový typ proti oficiální
   tabulce z Knihovny AutoCAD DJE (např. `408_ELESILAPV`, `602_VODNERNV`,
   `007_CNB`...). Neznámé hladiny (mimo tabulku) se pouze hlásí – nemažou se,
   protože mohou být záměrně přidané dodavatelem.
2. **Čárové typy** – zda jsou ve výkresu použity jen typy z knihovny ČEZ
   (řady `ISO-xx-x.xx`, `ZMZ_*`, `ELESILAPV`, `KANDESPV` apod.).
3. **Textové styly** – název a font proti 12 stylům ze šablony (řada
   ISO 3098: `ISO 3098 - A/B/BVL`, `ISOCP-BPVL`, `ISOCPEUR-BPVL`, `Azbuka`,
   `CALIBRI`, `Legend`, `Standard`, `Annotative`, `Spolocnost-Poloha`).
   **Odkud jsou tato data:** těch 12 stylů (název + font) je uloženo přímo
   v `CEZ_LAYERS_DATA.lsp` – vytáhl jsem je programově (přes `ezdxf`) z
   definic textových stylů uložených v oficiální šabloně
   `CEZ_Sablona vykresu podla VPC_REV2.dwt` (sekce "Knihovna AutoCAD DJE"
   na webu ČEZ). Nejde tedy o ruční přepis textu metodiky, ale o to, co
   šablona reálně obsahuje po instalaci. Kontrola nejdřív porovná
   *definice* stylů v tabulce `STYLE` výkresu (to jsou řádky bez
   souřadnic – jde o vlastnost stylu jako celku), a pak navíc projde
   konkrétní entity `TEXT`/`MTEXT`, které nevyhovující styl (nebo přímo
   `STANDARD`) používají, a u těch už uvede umístění – viz bod "Umístění
   nálezů" níže.
4. **Rámeček a popisové pole** – přítomnost bloku formátu (A0–A4, TL-A3,
   TL-A4) a bloku popisového pole (`Pole-1r`/`Pole-1z`/`Pole-2`/`Pole-3`).

   **Titulní list vs. pokračovací listy (důležité):** dle VP C (kap.
   "Zásady provedení dokumentu" → "Vícelistý dokument") se **plné**
   popisové pole se všemi údaji používá **jen na titulním listu**
   (bloky `Pole-1r`/`Pole-1z`). Na dalších listech vícelistého dokumentu
   se používá **jen** zjednodušený blok `Pole-2`/`Pole-3`, který
   **strukturálně neobsahuje** atributy `ČÍSLO_AKCE`, `STUPEŇ_PD`,
   `SO_DPS`, `DATUM`, `TYP`/`PODTYP`, `POŘ. Č.`, `MĚŘÍTKO`, `SCHVÁLIL`
   ani rezervní pole – to je **záměr metodiky**, ne chyba výkresu. Pokud
   tedy váš výkres má na 2. a dalších listech jen razítko firmy, název,
   soubor, vypracoval/kontroloval, arch. č., list a index, je to
   **v pořádku**. Kontrola proto rozlišuje typ nalezeného bloku a níže
   uvedené kontroly aplikuje jen tam, kde daný atribut vůbec existuje:
   - **ARCH_C** (dodavatelské číslo) – max. 15 znaků, jen `A-Z 0-9 - / .`
     dle kap. 3.1.4 standardu (na obou typech bloku)
   - **LOKALITA** – musí být EDU/JE Dukovany/Dukovany/ETE/JE Temelín/Temelín
     (na obou typech bloku)
   - **KTD** (kód třídy dokumentu) – musí mít 4 znaky, např. `DD04` (na
     obou typech bloku – `KTD` je jediný "obsahový" atribut, který mají
     `Pole-2`/`Pole-3` společný s `Pole-1r`/`Pole-1z`)
   - **NAZEV_1, VYPRACOVAL** – nesmí být prázdné (na obou typech bloku)
   - _pouze na titulním listu (`Pole-1r`/`Pole-1z`):_
     - **DATUM** – formát `dd.mm.rrrr`
     - **SO_DPS** – max. 12 znaků (VP C kap. 5.1.1)
     - **ČÍSLO_AKCE** – formát podle lokality: EDU = čtyřmístné číslo
       (např. `7709`), ETE = písmeno + trojmístné číslo (např. `B633`)
     - **STUPEŇ_PD** – nesmí být prázdné
     - **TYP** – informativní porovnání se známými příklady z VP C
       (`H16T`/`H16S`/`PPPt`/`PPPs`/`H01T`/`H01S`/`EDST`/`EDSS`); úplný
       číselník je ve volné příloze A, kterou nemám k dispozici, takže se
       neshoda jen vypíše jako info, ne jako chyba
   - vyplnění povinných polí (NAZEV_1, KTD, ČÍSLO_AKCE, STUPEŇ_PD, VYPRACOVAL)
5. **Barvy, čárové typy a tloušťky čar přímo na entitách** (ne ByLayer) –
   CEZ metodika přiřazuje tloušťku čáry při tisku podle **barvy** objektu
   (tiskové nastavení `cez_dje-ctb.ctb` je tzv. Color-Dependent Plot Style
   Table – tloušťka se určuje z barvy, ne z hladiny). Podle VP C kap. 3.4.4:
   barvy indexu **1–9** si při tisku zachovávají vlastní barvu (pro barevný
   výkres), barvy **10–254** se tisknou **černě** (kromě **103** = maskovací
   bílá a **254** = šedá pro bourané konstrukce) a **žlutá (ACI 2) a
   podobné světlé odstíny jsou vyloženě zakázané** na bílém podkladu tisku.
   Nástroj projde všechny entity a nahlásí, kde má barva/čárový typ/tloušťka
   nastavenou přímo na entitě místo "ByLayer", se zvláštním upozorněním na
   žlutou.
   - **5b) totéž uvnitř definic bloků** – bod 5 vidí jen entity přímo v
     modelovém/výkresovém prostoru; pokud má blok barvu "zapečenou" přímo
     ve své definici (typicky barevný symbol z knihovny), bod 5 ji
     nezachytí. Bod 5b prochází navíc všechny definice bloků a hlásí
     souhrnné počty (kolik entit uvnitř bloků má přímou barvu/čárový
     typ/tloušťku).
6. **Další pravidla podle volné přílohy C:**
   - **6a) Kódová stránka** – `DWGCODEPAGE` musí být `ANSI_1250` (čeština)
   - **6b) Kreslení v hladině "0"** – výslovně zakázáno ("Je nepřípustné
     kreslit v hladině 0")
   - **6c) Externí reference (XREF) a proxy grafika** – výkres je nesmí
     obsahovat
   - **6d) Text** – styl `STANDARD` se nesmí používat; výška písma musí
     být z povolené řady **10; 7; 5; 3,5; 3; 2,5; 2; 1,8 mm**; text nesmí
     být zrcadlený ani vzhůru nohama
   - **6e) Kótování** – kótovací styl (DIMENSION) by neměl být
     `Standard`/`Annotative`, ale odpovídat ČSN EN ISO 129-1 (`ISO_129-1`/
     `ISO-25` ze šablony)
   - **6f) CAD blok REVIZE** – vyplnění `OZNACENI_INDEX`, zákaz písmen
     `ch`/`o`/`x` a návaznost na existující hladinu `REVIZE_<index>`
   - **6g) CAD blok OZNAČENÍ** – atribut `SKRYTE_OZNACENI` nesmí obsahovat
     mezery (musí jít o strojově čitelné, "neviditelnými" znaky nezatížené
     označení projektové pozice dle SJZ)
7. **(jen v `CEZ-OPRAVA`) Dva interaktivní dotazy k barvám tisku:**
   - **7a) Volba tiskového stylu rozvržení** – nástroj se zeptá, zda chceš
     nastavit tiskový styl (Plot Style Table) všech rozvržení (layoutů)
     výkresu na:
     - **Černobílý dle VP C** (`cez_dje-ctb.ctb`) – barvy 10–254 se
       vytisknou černě, 1–9 si zachovají vlastní barvu, 103 = maskovací
       bílá, 254 = šedá
     - **Barevný** (`acad.ctb`) – každá barva se vytiskne jako ona sama
     - nebo přeskočit (Enter) a nic neměnit

     Tohle mění jen **odkaz** na plot style table – barvy ve výkresu
     samotném zůstávají beze změny.
   - **7b) Přepis základních indexových barev (1–9) na podobný odstín v
     rozsahu 10–254** – na rozdíl od 7a) tohle **trvale přepíše barvu**
     (DXF kód 62) na hladinách i přímo obarvených entitách podle tabulky:

     | Index | Barva | Nový index |
     |---|---|---|
     | 1 | červená | 10 |
     | 2 | žlutá | 50 |
     | 3 | zelená | 90 |
     | 4 | azurová | 130 |
     | 5 | modrá | 170 |
     | 6 | purpurová | 210 |
     | 7 | bílá/černá | beze změny |
     | 8 | tmavě šedá | 252 |
     | 9 | světle šedá | 253 |

     Smysl: barvy indexu 1–9 se dle VP C kap. 3.4.4 při tisku zachovávají
     ve vlastní barvě, zatímco barvy 10–254 se tisknou černě. Přepsáním
     na odpovídající index ve druhém rozsahu dostaneš vizuálně podobný
     odstín na obrazovce, ale při tisku už (bez ohledu na to, jaký přesně
     .ctb je zrovna nastavený) vyjde černě. Ptá se jen na `Ano`/`Ne`
     (výchozí Enter = Ne = nic se nemění).

## Co se opraví automaticky (`CEZ-OPRAVA`)

- barva/čárový typ hladiny, pokud hladina existuje v oficiální tabulce, ale
  má nastavenou jinou barvu/typ, než předepisuje šablona
- dodavatelské číslo (ARCH_C) obsahující malá písmena nebo mezery se převede
  na velká písmena bez mezer – **jen pokud výsledek splní i limit 15 znaků a
  povolenou znakovou sadu**, jinak se pouze nahlásí k ruční opravě
- čárový typ a tloušťka čáry (lineweight) nastavené přímo na entitě se
  převedou zpět na "ByLayer"
- `DWGCODEPAGE` se nastaví na `ANSI_1250`, pokud je jiná
- `SKRYTE_OZNACENI` v bloku OZNAČENÍ obsahující mezery se od mezer očistí
  (jen mezery, obsah textu se jinak nemění)
- **tiskový styl (Plot Style Table) všech rozvržení** – ale jen pokud na to
  na konci běhu odpovíš (interaktivní dotaz `Černobílé`/`Barevné`/
  `Přeskočit`); bez odpovědi (Enter) se nic nemění – viz bod 7a výše
- **základní indexové barvy 1–9** na hladinách i entitách – ale jen pokud
  na dotaz odpovíš `Ano`; bez odpovědi (Enter/Ne) se nic nemění – viz
  bod 7b výše

Vše ostatní (neznámé hladiny, neznámé textové styly, chybějící popisové pole,
prázdná povinná pole, kreslení v hladině "0", XREF/proxy grafika, styl
STANDARD na textu, nepovolená výška písma, zrcadlený text, nevhodný kótovací
styl, nekonzistentní blok REVIZE) nástroj **pouze hlásí** – jde o věci, které
vyžadují ruční zásah (překreslení, přesun geometrie na jinou hladinu apod.),
ne bezpečnou automatickou záměnu hodnoty.

**Barva nastavená přímo na entitě se automaticky NEOPRAVUJE** ani v režimu
`CEZ-OPRAVA` – dle ČEZ_ST_0093r06 kap. 3.6.3 se změny v dokumentaci
("Red correct"/tužkopis) smí záměrně odlišovat barevně ("zákres změn
graficky odlišen od původního provedení, např. barevně nebo podbarvením").
Automatická oprava by tak mohla smazat legitimní označení revize – nástroj
proto barevné override jen vypíše k ručnímu posouzení.

## Umístění nálezů (kde ve výkresu problém je)

Většina řádků `[POZOR]` u konkrétních entit (barvy/čárové typy/tloušťky v
bodě 5, hladina "0" v 6b, text v 6d, kótování v 6e, bloky REVIZE a
OZNAČENÍ v 6f/6g, i entity s nevyhovujícím textovým stylem v bodě 3) teď
obsahuje na konci `Nalezeno na: X=.. Y=.. prostor=.. hladina='..'
handle=..`:

- **X, Y** – souřadnice reprezentativního bodu entity (vkládací/počáteční/
  středový bod, DXF kód 10) v souřadném systému výkresu
- **prostor** – `Model` nebo `Papir/rozvrzeni` (aktuální výkresový prostor)
- **hladina** – na které hladině entita leží
- **handle** – jedinečný identifikátor entity. Nejrychlejší cesta k objektu
  je zpravidla podle souřadnic (např. `ZOOM` → `Window`/`Center` na dané
  X,Y); handle se hodí pro přesné dohledání skriptem – v AutoLISPu např.
  `(handent "1A2B")` vrátí referenci na danou entitu

U textových entit (`TEXT`) se navíc uvádí i krátký náhled samotného textu
(prvních 40 znaků), aby šel problematický nápis poznat na první pohled.

**Výjimka:** v bodě **5b** (barvy zapečené uvnitř *definic* bloků) souřadnice
nedávají smysl – žijí v lokálním souřadném systému bloku, ne ve výkresu.
Místo toho se u každého dotčeného bloku uvádí jeho název, kolikrát je ve
výkresu vložený, a souřadnice **prvního** vložení jako příklad, kde ho
hledat.

## Instalace

1. Zkopíruj oba soubory `CEZ_ST0093_Validator.lsp` a `CEZ_LAYERS_DATA.lsp`
   do jedné složky (musí zůstat spolu).
2. V AutoCADu: `Options` → záložka `Files` → `Support File Search Path` →
   `Add...` a přidej cestu k této složce (aby AutoCAD/AutoLISP soubor
   `CEZ_LAYERS_DATA.lsp` našel přes `findfile`).
3. Načti hlavní soubor příkazem `APPLOAD` (nebo přetažením `.lsp` souboru do
   plochy výkresu) → vyber `CEZ_ST0093_Validator.lsp` → `Load`.
4. V příkazové řádce by se mělo objevit:
   `[CEZ] Nacten validator/opravator CEZ_ST_0093 - prikazy: CEZ-KONTROLA, CEZ-OPRAVA`

Pokud chceš nástroj nahrávat automaticky při každém spuštění AutoCADu, přidej
řádek do `acaddoc.lsp` (nebo `S::STARTUP`):
```lisp
(load "C:/cesta/k/CEZ_ST0093_Validator.lsp")
```

## Použití

- `CEZ-KONTROLA` – spustí kompletní kontrolu, výsledek vypíše do příkazové
  řádky a uloží jako textový log vedle výkresu
  (`<název_výkresu>_CEZ_kontrola.log`).
- `CEZ-OPRAVA` – totéž, navíc provede bezpečné automatické opravy popsané
  výše a uloží log `<název_výkresu>_CEZ_oprava.log`. Po opravě provede
  `REGEN`.

**Doporučení:** před prvním použitím `CEZ-OPRAVA` na ostrém výkresu si
udělej zálohu (nebo spusť nejdřív `CEZ-KONTROLA`, zkontroluj log a teprve
pak `CEZ-OPRAVA`).

## Známá omezení

- Nástroj jsem sestavil na základě analýzy veřejně dostupné metodiky ČEZ
  (staženo z webu dodavatelské sekce cez.cz a doplněno standardem
  ČEZ_ST_0093r06), ale **nebyl odzkoušen v reálném AutoCADu** – v prostředí,
  kde vznikal, licence AutoCADu není k dispozici. Doporučuji před nasazením
  do praxe otestovat na kopii zkušebního výkresu.
- Kontrola popisového pole hledá bloky `Pole-1r/1z/2/3` vložené přímo ve
  výkresu (ne vnořené o úroveň hlouběji uvnitř jiného bloku). Pokud vaše
  praxe vkládá popisové pole jinak, bude potřeba upravit funkci
  `cez-find-popisove-pole` / `cez-collect-inserts-by-name`.
- Nástroj teď vychází z **plného textu volné přílohy C** (poskytnuté
  uživatelem) i z hlavního standardu ČEZ_ST_0093r06. Neimplementované
  zůstávají věci, které nejsou spolehlivě strojově ověřitelné z geometrie
  výkresu, hlavně:
  - přesná velikost formátu (max. 891×2520 mm pro nové výkresy) – vyžaduje
    čtení nastavení layoutu/plot setup přes ActiveX, není implementováno
  - obsahová správnost kreslení (technické kreslení, normy zobrazení
    zařízení) – to je vždy věc inženýrského posouzení
  - "podobné světlé odstíny" barev vedle vyloženě zakázané žluté (ACI 2) –
    nástroj hlásí přesně žlutou, ostatní "světlé" barvy by vyžadovaly plnou
    tabulku RGB hodnot ACI palety a výpočet jasu, což není implementováno
  - VP A (Seznam tříd dokumentů a jejich kódů) není k dispozici, takže
    kontrola pole TYP/KTD proti úplnému číselníku je jen informativní
- **Volba tiskového stylu (bod 7)** mění jen *odkaz* na plot style table
  (`StyleSheet` v layoutu) – soubor `cez_dje-ctb.ctb` samotný musí být už
  nahraný ve složce Plot Styles AutoCADu (viz `Návod pro použití šablony a
  načtení pomocných souborů.pdf` v `reference/`), jinak AutoCAD při tisku
  nahlásí, že plot style nenašel. Funkce navíc před dotazem zkontroluje
  `PSTYLEMODE` (musí být `1` = Color Dependent Plot Style/.ctb) a upozorní,
  pokud výkres používá pojmenované plot styly (`.stb`) místo barevně
  závislých.

## Opravy (changelog)

- **Oprava falešných chyb na pokračovacích listech (Pole-2/Pole-3):**
  kontrola popisového pole dřív vyžadovala vyplnění `ČÍSLO_AKCE` a
  `STUPEŇ_PD` na *všech* nalezených popisových polích, včetně bloků
  `Pole-2`/`Pole-3`, které tyto atributy vůbec strukturálně neobsahují
  (existují jen v `Pole-1r`/`Pole-1z`) – to hlásilo "pole je prázdné" i na
  zcela správně vyplněných pokračovacích listech. Kontrola teď nejdřív
  podle názvu nalezeného bloku pozná, jde-li o titulní list (plné pole)
  nebo pokračovací list (zjednodušené pole), a atributy, které daný typ
  bloku vůbec nemá, se přeskakují. Viz upřesnění v bodě 4 výše.

- **Umístění nálezů (souřadnice) v hlášeních:** přidána funkce
  `cez-entity-loc-str`, která ke každému nálezu u konkrétní entity (bod 3
  – použití nevyhovujícího textového stylu, bod 5, 6b, 6d, 6e, 6f, 6g)
  připojí souřadnice, prostor (Model/Papír), hladinu a handle – viz nová
  sekce "Umístění nálezů" výše. U textových entit se navíc přidal náhled
  samotného textu (`cez-text-preview`). Kontrola textových stylů (bod 3)
  byla rozšířena o druhý průchod, který kromě definic stylů v tabulce
  `STYLE` (bez umístění – je to vlastnost stylu, ne konkrétního textu)
  najde i konkrétní `TEXT`/`MTEXT` entity používající nevyhovující styl
  a u nich už umístění uvede. Bod 5b (barvy uvnitř definic bloků) byl
  rozšířen o výpis dotčených bloků se jménem, počtem vložení a souřadnicí
  prvního vložení coby příkladu, kde blok hledat.

- **Log: zvýraznění `[POZOR]` a počet nalezených problémů nahoře:** každý
  řádek `[POZOR]` v generovaném `.txt` logu (i na příkazové řádce) teď má
  před sebou `!!!` (`!!! [POZOR]  ...`), aby šel snáz najít. Hned pod
  řádkem `Datum:` v hlavičce logu navíc přibyl řádek `Pocet nalezenych
  chyb neodpovidajicich metodice: N` s celkovým počtem – nemusíš log
  procházet celý, abys zjistil, kolik problémů kontrola našla.

- **Oprava: přepis barev (bod 7b) nefungoval na barvy "zapečené" uvnitř
  definice bloku.** `ssget "_X"`, který používají kontrola barev (bod 5) i
  původní přepis (bod 7b), vrátí jen entity přímo v modelovém/výkresovém
  prostoru (včetně samotných INSERT referencí) – ale **ne** entity, které
  jsou součástí definice bloku (tj. geometrii, kterou blok obsahuje). Pokud
  má taková entita barvu natvrdo nastavenou přímo v definici bloku (ne
  `ByBlock`/`ByLayer`), zůstala touto cestou nedotčená – blok tak po vložení
  do výkresu vypadal stále stejně, i po `CEZ-OPRAVA`. Přidána nová funkce
  `cez-remap-colors-in-block-defs`, která navíc prochází **všechny definice
  bloků** (`(tblnext "BLOCK")`) a přepisuje barvy i tam – volá se
  automaticky jako součást bodu 7b. Zároveň přidána souhrnná kontrola
  **5b) Barvy/čárové typy/tloušťky uvnitř definic bloků**, aby totéž hlásila
  i `CEZ-KONTROLA` (bez tohoto doplnění by kontrola bloky se zapečenou
  barvou vůbec nezmínila).

- **Aktualizace na ČEZ_ST_0093r06** (revize 06, účinná od 31.03.2026):
  prošel jsem celý přehled změn proti r05 (viz kap. 1.3 nového dokumentu).
  Většina změn se týká administrativní/procesní stránky, která nemá vliv
  na obsah tohoto nástroje – přejmenování zkratek (DZVU→DZV, PDPoS→PDSŘ),
  příprava na bezpapírový oběh dokumentů, "Tagované PDF A", nové volné
  přílohy Aa/Ab (lešení, technologický postup). Věcně jsem ověřil, že
  pravidla, která tento nástroj kontroluje, zůstávají v r06 **beze
  změny obsahu** – jen přečíslovaná:
  - popisové pole, dodavatelské číslo, LOKALITA (kap. 3.1.3–3.1.6) – čísla
    kapitol stejná, obsah stejný (jen "krycí list" přejmenován na "titulní
    list" a přidán příklad "+" jako dalšího nepovoleného znaku, což už
    kontrola `cez-chars-ok-p` odjakživa odmítala)
  - značení revizí písmeny a zákaz `ch`/`o`/`x` (`i` navíc pro OS) –
    **přečíslováno z kap. 3.5.3 na kap. 3.4.1.3**, obsah stejný → opraven
    odkaz v kódu (funkce `cez-check-revize`)
  - barevné odlišení revizí "Red correct" – **zůstalo na kap. 3.6.3**,
    obsah stejný, žádná změna v kódu potřeba
  - VP C: dle přehledu změn se v r06 upravila kap. 3.4.1 (formáty
    výkresových listů – odstraněna tabulka s výčtem přípustných formátů,
    nahrazena odkazem na šablonu a normu ČSN EN ISO 5457/216) a kap. 3.4.3
    (výčet povolených čar nahrazen odkazem na šablonu – to už tento
    nástroj dělá, čte čárové typy přímo ze šablony, ne z pevného
    seznamu). Kapitoly o barvách čar (3.4.4), písmu (3.4.5), kótování
    (3.4.6), revizích (3.5) a značení pozic (3.7), které tento nástroj
    přímo kontroluje, **nejsou v přehledu změn VP C zmíněné** – tedy
    v r06 nezměněné. Aktuální plný text VP C k r06 (jako samostatný
    dokument) k dispozici nemám – pokud ho seženeš, ráda ho projdu znovu
    a případně doplním kap. 3.4.1 (formáty) do kontroly.
  - Aktualizovány všechny odkazy na revizi standardu v komentářích a
    hláškách skriptu z r05 na r06.



- **Přepis základních indexových barev 1–9 na odstín v rozsahu 10–254
  (bod 7b) v `CEZ-OPRAVA`:** nový interaktivní dotaz, který na požádání
  trvale přepíše barvu (DXF 62) hladin i přímo obarvených entit z
  indexu 1–9 na odpovídající index 10/50/90/130/170/210/252/253 (barva 7
  se nemění) – viz tabulka v sekci 7b výše. Zároveň byla oprava barvy
  hladiny v bodě 1 (`CEZ-KONTROLA`/`CEZ-OPRAVA` proti oficiální tabulce)
  přepsána z příkazového makra `-LAYER` na přímou úpravu tabulkového
  záznamu přes `entmod` (`tblobjname "LAYER" ...`) – spolehlivější a
  méně náchylné na přesné pořadí promptů příkazové řádky.
- **Volba tiskového stylu (černobílý/barevný) v `CEZ-OPRAVA`:** na konci
  běhu opravy se nástroj nově interaktivně zeptá, zda přepnout plot style
  table všech rozvržení na CEZ černobílý (`cez_dje-ctb.ctb`, dle VP C kap.
  3.4.4) nebo na barevný (`acad.ctb`) – viz bod 7 výše. Beze změny se
  přeskočí (Enter).
- **Doplnění kontrol dle plného textu volné přílohy C:** přidána sekce 6
  (kódová stránka, zákaz hladiny "0", zákaz XREF/proxy grafiky, styl
  STANDARD a výšky písma, zrcadlený text, kótovací styl, blok REVIZE, blok
  OZNAČENÍ) a rozšířena kontrola popisového pole o SO_DPS, ČÍSLO_AKCE dle
  lokality, KTD a TYP. Zpřesněna i kontrola barev na entitách o konkrétní
  pravidla VP C kap. 3.4.4 (1–9 vlastní barva, 10–254 černá kromě
  103/254, žlutá zakázaná).
- **Oprava kontroly povolených znaků dodavatelského čísla:** funkce
  `cez-chars-ok-p` používala `wcmatch` se vzorem typu `[ABC...9-/.]`. Uvnitř
  hranatých závorek `wcmatch` ale pomlčku interpretuje jako **operátor
  rozsahu** (stejně jako `[A-Z]`), takže `9-/` se vyhodnotilo jako (chybný)
  rozsah od znaku `9` do znaku `/`, a samotná pomlčka i lomítko pak byly
  vyhodnoceny jako nepovolené znaky. Proto číslo jako `TES-Z-25-450/04`
  (obsahuje pomlčku i lomítko) neprošlo kontrolou, i když je platné. Funkce
  teď hledá každý znak jako podřetězec pomocí `vl-string-search` – žádná
  interpretace pomlčky jako rozsahu.
- **Oprava chyby v názvu atributu:** pole "Číslo akce" mělo v kontrole popisového
  pole chybně zapsaný tag jako `CISLO_AKCE` (bez háčku), zatímco skutečný tag
  v šabloně je `ČISLO_AKCE` – kontrola proto pole vždy vyhodnotila jako prázdné/
  chybějící, i když bylo vyplněné správně. Opraveno.
- **Zápis diakritiky přes `\U+XXXX`:** všechny řetězce s českou diakritikou,
  které se porovnávají s daty z výkresu (tagy atributů `ČISLO_AKCE`,
  `STUPEŇ_PD`, název bloku `Rámeček`, hodnoty pole LOKALITA jako "Temelín"),
  jsou teď zapsané pomocí AutoLISP escape sekvence `\U+XXXX` (např. `\U+010D`
  = č) místo přímých UTF-8 znaků. Díky tomu porovnání funguje spolehlivě bez
  ohledu na to, jakou kódovou stránku AutoCAD při načítání `.lsp` souboru
  použije – přímo zapsaná diakritika se totiž v závislosti na kódování snadno
  "rozbije" a porovnání pak tiše selže (přesně to způsobilo první chybu výše).

## Zdroj dat

- https://www.cez.cz/cs/pro-dodavatele/pozadavky-na-dodavatele-pro-je/pozadavky-na-projektovou-dokumentaci-2
  – sekce "Knihovna AutoCAD DJE" (šablona, .ctb, .lin/.shx) a "Metodika pro
  zpracování průkazné dokumentace SKK"
- `ČEZ_ST_0093r06.pdf` – hlavní standard, revize 06 (poskytnutý uživatelem)
- `VP_C_Pozadavky_na_vykres.docx` – volná příloha C, "Požadavky na výkres"
  (poskytnutá uživatelem; odpovídá revizi r05 hlavního standardu – dle
  přehledu změn v r06 jsou ale kapitoly, které tento nástroj kontroluje,
  obsahově nezměněné, viz changelog výše)
