;; ============================================================================
;; CEZ_ST0093_Validator.lsp
;;
;; Validator/opravator vykresove dokumentace AutoCAD dle metodiky CEZ, a.s.
;; pro dodavatele JE (ETE/EDU) - CEZ_ST_0093r06 "Pozadavky na projektovou
;; a souvisejici dokumentaci" a jeji VOLNA PRILOHA C "Pozadavky na vykres"
;; (plny text), ve spojeni se sablonou "CEZ_Sablona vykresu podla
;; VPC_REV2.dwt" (Knihovna AutoCAD DJE, standard revize 3 a vyssi).
;;
;; Kontroluje:
;;   1. Hladiny (nazev, barva, carovy typ) proti oficialni tabulce hladin
;;   2. Carove typy pouzite ve vykresu proti seznamu povolenych typu
;;   3. Textove styly (nazev + font) proti seznamu povolenych stylu (ISO 3098)
;;   4. Pritomnost ramecku (blok "Ramecek") a popisoveho pole (blok
;;      "Pole-1r"/"Pole-1z"/"Pole-2"/"Pole-3") + vyplneni a format
;;      klicovych atributu popisoveho pole dle kap. 3.1.4-3.1.6 CEZ_ST_0093
;;      a kap. 5.1.1 VP C (vc. delky SO_DPS, formatu cisla akce dle
;;      lokality EDU/ETE, delky KTD, informativne i kodu TYP)
;;   5. Barvy/carove typy/tloustky car nastavene PRIMO na entitach misto
;;      ByLayer, vc. vyslovne zakazane zlute barvy (ACI 2) dle VP C kap.
;;      3.4.4 (viz sekce 5 nize). 5b) navic souhrnne kontroluje totez
;;      UVNITR DEFINIC BLOKU (ssget "_X" v 5) tam nevidi - viz POZOR
;;      nize).
;;   6. Dalsi pravidla dle VOLNE PRILOHY C:
;;      6a) kodova stranka vykresu (DWGCODEPAGE musi byt ANSI_1250)
;;      6b) zakaz kresleni primo v hladine "0"
;;      6c) zakaz externich referenci (XREF) a proxy grafiky
;;      6d) zakaz stylu STANDARD na textu, povolena rada vysek pisma
;;          (10/7/5/3,5/3/2,5/2/1,8 mm), zakaz zrcadleneho/obraceneho textu
;;      6e) kotovaci styl DIMENSION by nemel byt Standard/Annotative
;;          (ma byt ISO_129-1/ISO-25 dle CSN EN ISO 129-1)
;;      6f) CAD blok REVIZE - vyplneni OZNACENI_INDEX a navaznost na
;;          hladinu REVIZE_xx
;;      6g) CAD blok OZNACENI - SKRYTE_OZNACENI nesmi obsahovat mezery
;;
;; UMISTENI NALEZU (kde ve vykresu se problem nachazi):
;; Vetsina radku [POZOR] u konkretnich entit (sekce 3 pozdejsi cast, 5, 6b,
;; 6d, 6e, 6f, 6g) obsahuje "Nalezeno na: X=.. Y=.. prostor=.. hladina=..
;; handle=.." (funkce cez-entity-loc-str) - souradnice reprezentativniho
;; bodu entity (insercni/pocatecni/stredovy bod), zda je entita v Modelu
;; nebo v Papiru/rozvrzeni, hladinu a handle entity (pro pripadne dohledani
;; pres prikaz AutoCADu, ktery umoznuje vybrat entitu podle handle). U TEXT
;; entit se navic uvadi i nahled samotneho textu (cez-text-preview). Vyjimka
;; je sekce 5b (barvy uvnitr DEFINIC bloku) - tam souradnice nedavaji smysl
;; (jsou v lokalnim souradnem systemu bloku, ne ve vykresu), misto toho se
;; uvadi nazev bloku, pocet jeho vlozeni ve vykresu a souradnice PRVNIHO
;; vlozeni jako priklad, kde blok hledat.
;;   7. (jen v CEZ-OPRAVA) dva interaktivni dotazy tykajici se barev tisku:
;;      7a) nastavit tiskovy styl (Plot Style Table) vsech rozvrzeni na
;;          CEZ cernobily dle VP C (cez_dje-ctb.ctb) nebo na barevny
;;          (acad.ctb) - meni jen ODKAZ na .ctb soubor, ne barvy ve
;;          vykresu
;;      7b) primo PREPSAT barvu (DXF 62) hladin a primo obarvenych entit,
;;          ktere maji zakladni indexovou barvu 1-9, na odpovidajici
;;          index v rozsahu 10-254 se stejnym/podobnym odstinem (dle
;;          tabulky zadane uzivatelem - viz sekce 7b nize). Toto NENI
;;          totez co 7a) - 7b) trvale meni data ve vykresu, 7a) jen
;;          nastavuje, jak se maji existujici barvy pri tisku vylozit.
;;
;; Prikazy:
;;   CEZ-KONTROLA   - spusti kompletni kontrolu, vysledek vypise do prikazove
;;                    radky a ulozi do textoveho souboru vedle vykresu
;;   CEZ-OPRAVA     - jako kontrola, navic se pokusi bezpecne opravit to, co
;;                    lze opravit automaticky beze ztraty dat (viz nize)
;;   CEZ-VERZE      - zjisti a vypise mistni verzi vs. nejnovejsi verzi na
;;                    GitHubu (jen cte, nic nemeni) - vyzaduje AutoCAD pro
;;                    Windows a pripojeni k internetu
;;   CEZ-UPDATE     - stahne nejnovejsi verzi z GitHubu (Chuck3CZ/
;;                    cez-autocad-validator) a prepise mistni soubory -
;;                    viz sekce 8 nize a README.md ("Automaticke nacitani
;;                    a aktualizace")
;;
;; Funkce cez-enable-autorun-on-open (volana z acaddoc.lsp, NENI aktivni
;; sama od sebe) zapne automaticke spusteni CEZ-KONTROLA pri KAZDEM
;; otevreni/zalozeni vykresu, vc. (alert) upozorneni pri nalezenych
;; problemech - viz sekce 9 nize a README.md ("Automaticke spusteni
;; kontroly pri otevreni vykresu").
;;
;; Co se OPRAVUJE automaticky (CEZ-OPRAVA):
;;   - hladina existujici v oficialni tabulce, ale s jinou barvou/carovym
;;     typem nez predepisuje sablona -> nastavi se spravna barva/carovy typ
;;   - chybejici carovy typ pouzity na hladine, ktery lze nacist ze
;;     souboru acadiso.lin/vlastniho .lin (pokud je definovan a dostupny
;;     v Support File Search Path) -> pokus o LINETYPE Load
;;   - dodavatelske cislo v atributu ARCH_C obsahujici mala pismena nebo
;;     mezery -> prevod na velka pismena, odstraneni mezer (POUZE pokud
;;     vysledek respektuje povoleny znakovy rozsah a max. 15 znaku;
;;     jinak se jen nahlasi, aby nedoslo k tichemu po\U+0161kozeni cisla)
;;   - carovy typ nebo tloustka cary (lineweight) nastavene primo na
;;     entite se prevedou zpet na ByLayer
;;   - DWGCODEPAGE se nastavi na ANSI_1250, pokud je jiny
;;   - SKRYTE_OZNACENI v bloku OZNACENI obsahujici mezery se ocisti
;;     (mezery se odstrani) - opet jen pokud jde jednoznacne o mezery,
;;     obsah textu se jinak nemeni
;;   - tiskovy styl (Plot Style Table) vsech rozvrzeni se NA VYZADANI
;;     (interaktivni dotaz na konci behu CEZ-OPRAVA) nastavi na
;;     cez_dje-ctb.ctb (cernobily tisk dle VP C) nebo acad.ctb (barevny
;;     tisk) - viz sekce 7a. Bez odpovedi (Enter/Preskocit) se nic nemeni.
;;   - zakladni indexove barvy 1-9 (hladin i primo obarvenych entit) se
;;     NA VYZADANI (dalsi interaktivni dotaz) prepisi na odpovidajici
;;     index v rozsahu 10-254 dle tabulky v sekci 7b. Bez odpovedi
;;     (Enter/Ne) se nic nemeni.
;;
;; Co se POUZE HLASI (protoze oprava vyzaduje inzenyrske rozhodnuti):
;;   - neznama hladina (neni v oficialni tabulce CEZ) - muze jit o zamerne
;;     pridanou hladinu dodavatele, proto se nemaze ani nepreklada sama
;;   - neznamy/nepovoleny textovy styl nebo font
;;   - chybejici blok Ramecek / popisove pole
;;   - prazdna nebo spatne formatovana povinna pole popisoveho pole
;;   - dodavatelske cislo delsi nez 15 znaku po ocisteni
;;   - barva nastavena primo na entite (ne ByLayer, vc. zlute ACI 2) -
;;     NEOPRAVUJE se automaticky, protoze CEZ_ST_0093r06 kap. 3.6.3
;;     pripousti barevne odliseni revizi ("Red correct") - muze jit
;;     o zamer, ne o chybu (zluta vsak dle VP C neni prijatelna nikdy,
;;     i to se ale jen hlasi, aby se pripadne nesmazalo neco dulezitejsiho)
;;   - kresleni v hladine "0", externi reference, proxy grafika, styl
;;     STANDARD na textu, nepovolena vyska pisma, zrcadleny text, spatny
;;     kotovaci styl, nekonzistentni blok REVIZE/hladina REVIZE_xx -
;;     vsechny tyto veci vyzaduji rucni zasah (prekresleni/premisteni),
;;     ne bezpecnou automatickou zamenu hodnoty
;;
;; POZOR / OMEZENI:
;;   - Skript vychazi z verejne dostupnych souboru metodiky CEZ (sablona
;;     DWT, standard CEZ_ST_0093r06). Nebyl testovan v realnem AutoCADu
;;     (bezel v prostredi bez licence AutoCADu) - pred ostrym pouzitim
;;     doporucujeme otestovat na kopii existujiciho vykresu.
;;   - Kontrola popisoveho pole cte atributy z PRIMYCH insertu bloku
;;     "Pole-1r/1z/2/3" ve vykresu (ne vnorenych o uroven hloub\U+011Bji).
;;     Pokud vas vykres pouziva jiny zpusob vkladani razitka, uprav
;;     funkci cez-find-popisove-pole.
;;   - Barvy/carove typy/tloustky "primo na entite" se v sekci 5 a v 7b
;;     kontroluji/opravuji na DVOU mistech: (1) entity primo v modelovem
;;     a papirovem prostoru pres ssget "_X" a (2) entity ULOZENE UVNITR
;;     DEFINIC BLOKU pres pruchod (tblnext "BLOCK"). Pokud ma blok barvu
;;     "zapecenou" primo ve sve definici (nikoli ByBlock/ByLayer), byla
;;     puvodne (pred touto opravou) touto opravou preskocena, protoze
;;     ssget "_X" dovnitr definic bloku nevidi. Nyni jsou obe mista
;;     pokryta (funkce cez-remap-colors-in-block-defs pro 7b a
;;     cez-check-block-def-colors pro souhrnnou kontrolu v 5b).
;;   - Vsechny znaky s ceskou diakritikou (tagy atributu jako
;;     "\U+010CISLO_AKCE"/"STUPE\U+0147_PD", nazev bloku "R\U+00E1me\U+010Dek", hodnoty
;;     LOKALITA apod.) jsou v tomto souboru zapsany pomoci \U+XXXX escape
;;     sekvence (napr. \U+010D = c s hackem) misto primych UTF-8 znaku.
;;     Toto je zamerne - AutoLISP takto zapsane retezce interpretuje
;;     spravne bez ohledu na kodovou stranku, na ktere .lsp soubor
;;     AutoCAD nacte. Pokud budes do skriptu pridavat dalsi retezce
;;     s diakritikou, pouzij stejny zapis (napr. Rezerva 1 v komentarich
;;     muze zustat bez diakritiky, ale hodnoty porovnavane s atributy
;;     vykresu musi diakritiku respektovat presne).
;; ============================================================================

;; Zajisti nacteni Visual LISP rozsireni (vl-string-search, vl-filename-base...)
(vl-load-com)

;; Verze tohoto nastroje a umisteni na GitHubu (pro CEZ-VERZE / CEZ-UPDATE)
(setq *cez-validator-version* "1.4.0")
(setq *cez-github-repo* "Chuck3CZ/cez-autocad-validator")
(setq *cez-github-branch* "main")

;; Globalni pocitadlo radku [POZOR] pro aktualni beh CEZ-KONTROLA/CEZ-OPRAVA
;; (resetuje se na zacatku cez-run)
(setq *cez-pozor-count* 0)

;; ---- Nacteni datove tabulky hladin/carovych typu/textovych stylu --------
(defun cez-load-data ( / path)
  (setq path (findfile "CEZ_LAYERS_DATA.lsp"))
  (if path
    (load path)
    (progn
      (princ "\n[CEZ] CHYBA: soubor CEZ_LAYERS_DATA.lsp nebyl nalezen na Support File Search Path.")
      (princ "\n[CEZ] Uloz jej do stejne slozky jako tento .lsp a pridej tuto slozku do Options > Support File Search Path.")
    )
  )
)

;; Povolene hodnoty pole LOKALITA (kap. 3.1.3 CEZ_ST_0093r06)
(setq *cez-lokality* (list "EDU" "JE Dukovany" "Dukovany" "ETE" "JE Temelin" "JE Temel\U+00EDn" "Temelin" "Temel\U+00EDn"))

;; Povolene znaky pro dodavatelske cislo (kap. 3.1.4 bod 4b): A-Z 0-9 - / .
(setq *cez-arch-c-ok* "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-/.")

;; Nazvy bloku popisoveho pole a ramecku dle sablony CEZ
(setq *cez-blok-ramecek* "Ramecek")             ;; realny nazev ve sablone je "R\U+00E1me\U+010Dek" - viz cez-name-variants
(setq *cez-bloky-pole* (list "Pole-1r" "Pole-1z" "Pole-2" "Pole-3"))

;; ----------------------------------------------------------------------
;; Pomocne funkce
;; ----------------------------------------------------------------------

(defun cez-log (msg / )
  (setq *cez-report* (cons msg *cez-report*))
  (princ (strcat "\n" msg))
  (princ)
)

;; Zapise radek jen do *cez-report* (do log souboru), BEZ vypisu do prikazove
;; radky - pouziva se pro placeholder pocitadla POZOR, ktery se pred zapisem
;; souboru dodatecne nahradi skutecnym poctem (viz cez-run).
(defun cez-log-silent (msg / )
  (setq *cez-report* (cons msg *cez-report*))
)

(defun cez-ok (msg) (cez-log (strcat "  [OK]     " msg)))
(defun cez-warn (msg)
  (setq *cez-pozor-count* (1+ *cez-pozor-count*))
  (cez-log (strcat "  !!! [POZOR]  " msg))
)
(defun cez-fix (msg) (cez-log (strcat "  [OPRAVA] " msg)))
(defun cez-fail (msg) (cez-log (strcat "  [CHYBA]  " msg)))

(defun cez-str-upper (s) (strcase s))

;; Odstrani mezery ze stringu
(defun cez-str-nospace (s / out i c)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (/= c " ") (setq out (strcat out c)))
    (setq i (1+ i))
  )
  out
)

;; Vrati T, pokud vsechny znaky retezce s jsou obsazeny v povolene mnozine allowed.
;; POZOR: NEPOUZIVAT wcmatch s "[" allowed "]" - pomlcka uvnitr hranatych zavorek
;; se ve vzoru wcmatch chova jako operator rozsahu (napr. "[9-/]" neni "znak 9,
;; znak -, znak /", ale (spatny/obraceny) rozsah od '9' do '/'), takze by se
;; pomlcka a lomitko v dodavatelskem cisle (napr. "TES-Z-25-450/04") chybne
;; vyhodnotily jako nepovolene znaky. Misto toho hledame kazdy znak jako
;; podretezec v "allowed" pomoci vl-string-search - zadna zvlastni interpretace
;; pomlcky, teckyy ani lomitka.
(defun cez-chars-ok-p (s allowed / i ok c)
  (setq i 1 ok T)
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (if (not (vl-string-search c allowed))
      (setq ok nil)
    )
    (setq i (1+ i))
  )
  ok
)

;; Vyhledani zaznamu hladiny v *cez-layers* dle jmena (case-sensitive, jak AutoCAD ulozi)
(defun cez-layer-lookup (name / rec found)
  (setq found nil)
  (foreach rec *cez-layers*
    (if (= (strcase (car rec)) (strcase name)) (setq found rec))
  )
  found
)

(defun cez-linetype-known-p (name)
  (or (member (strcase name) (mapcar 'strcase *cez-linetypes*))
      (member (strcase name) (list "CONTINUOUS" "BYLAYER" "BYBLOCK")))
)

(defun cez-textstyle-lookup (name / rec found)
  (setq found nil)
  (foreach rec *cez-textstyles*
    (if (= (strcase (car rec)) (strcase name)) (setq found rec))
  )
  found
)

;; Nastavi barvu (a volitelne carovy typ) hladiny primo pres tabulkovy zaznam
;; (entmod nad (tblobjname "LAYER" ...)) - spolehlivejsi nez prikazove makro
;; "-LAYER", ktere je citlive na presnou posloupnost promptu.
;; newlinetype = nil znamena "nemenit carovy typ hladiny".
(defun cez-layer-set-color-linetype (name newcolor newlinetype / lname elist oldcolor)
  (setq lname (tblobjname "LAYER" name))
  (if lname
    (progn
      (setq elist (entget lname))
      (setq oldcolor (cdr (assoc 62 elist)))
      (setq elist (subst (cons 62 (if (< oldcolor 0) (- newcolor) newcolor))
                          (assoc 62 elist) elist))
      (if newlinetype
        (setq elist (subst (cons 6 newlinetype) (assoc 6 elist) elist))
      )
      (entmod elist)
      T
    )
    nil
  )
)

;; ----------------------------------------------------------------------
;; 1) Kontrola / oprava hladin
;; ----------------------------------------------------------------------
(defun cez-check-layers (fix-p / tbl name color ltype rec n-ok n-warn n-fix n-unknown)
  (cez-log "\n=== 1) KONTROLA HLADIN (LAYERS) ===")
  (setq n-ok 0 n-warn 0 n-fix 0 n-unknown 0)
  (setq tbl (tblnext "LAYER" T))
  (while tbl
    (setq name  (cdr (assoc 2 tbl))
          color (cdr (assoc 62 tbl))
          ltype (cdr (assoc 6 tbl)))
    (if (< color 0) (setq color (- color))) ;; zaporne cislo = vypnuta hladina
    (setq rec (cez-layer-lookup name))
    (cond
      ((null rec)
        (setq n-unknown (1+ n-unknown))
        (cez-warn (strcat "Hladina '" name "' neni v oficialni tabulce CEZ (Knihovna AutoCAD DJE). "
                           "Zkontroluj, zda nejde o preklep nebo neschvalenou hladinu."))
      )
      ((and (= color (cadr rec)) (= (strcase ltype) (strcase (caddr rec))))
        (setq n-ok (1+ n-ok))
      )
      (t
        (setq n-warn (1+ n-warn))
        (cez-warn (strcat "Hladina '" name "' ma barvu " (itoa color) "/carovy typ '" ltype
                           "', ma byt barva " (itoa (cadr rec)) "/carovy typ '" (caddr rec) "'."))
        (if fix-p
          (progn
            (if (cez-linetype-known-p (caddr rec))
              (progn
                (cez-layer-set-color-linetype name (cadr rec) (caddr rec))
                (setq n-fix (1+ n-fix))
                (cez-fix (strcat "Hladina '" name "' opravena na barvu " (itoa (cadr rec))
                                  "/carovy typ '" (caddr rec) "'."))
              )
              (cez-warn (strcat "Carovy typ '" (caddr rec) "' pro hladinu '" name
                                 "' neni v aktualnim vykresu nacten - oprava barvy/typu preskocena. "
                                 "Nejprve nacti carove typy ze slozky 'Definicni soubory car lin a shx'."))
            )
          )
        )
      )
    )
    (setq tbl (tblnext "LAYER"))
  )
  (cez-log (strcat "Shrnuti hladin: OK=" (itoa n-ok) ", odlisne=" (itoa n-warn)
                    ", opraveno=" (itoa n-fix) ", neznamych=" (itoa n-unknown)))
)

;; ----------------------------------------------------------------------
;; 2) Kontrola carovych typu pouzitych ve vykresu (na hladinach i primo na entitach)
;; ----------------------------------------------------------------------
(defun cez-check-linetypes ( / tbl name n-ok n-unknown)
  (cez-log "\n=== 2) KONTROLA CAROVYCH TYPU ===")
  (setq n-ok 0 n-unknown 0)
  (setq tbl (tblnext "LTYPE" T))
  (while tbl
    (setq name (cdr (assoc 2 tbl)))
    (if (cez-linetype-known-p name)
      (setq n-ok (1+ n-ok))
      (progn
        (setq n-unknown (1+ n-unknown))
        (cez-warn (strcat "Ve vykresu je nacten carovy typ '" name "', ktery neni v knihovne CEZ "
                           "(ZMZ_*.lin ani vestavene ISO rady sablony)."))
      )
    )
    (setq tbl (tblnext "LTYPE"))
  )
  (cez-log (strcat "Shrnuti carovych typu: OK=" (itoa n-ok) ", neznamych=" (itoa n-unknown)))
)

;; ----------------------------------------------------------------------
;; 3) Kontrola textovych stylu
;; ----------------------------------------------------------------------
;; Zdroj dat: seznam povolenych stylu (*cez-textstyles*, viz CEZ_LAYERS_DATA.lsp)
;; je extrahovan primo z DEFINIC textovych stylu ulozenych v oficialni sablone
;; "CEZ_Sablona vykresu podla VPC_REV2.dwt" (Knihovna AutoCAD DJE) - tzn. presne
;; tech 12 stylu (nazev+font), ktere sablona obsahuje po nainstalovani dle Navodu
;; pro pouziti sablony. Neni to text VP C samotne, ale co je fakticky v sablone.
;;
;; Tato funkce kontroluje DVE veci:
;;  a) definice stylu v tabulce STYLE aktualniho vykresu (jestli existujici
;;     styl odpovida nazvem+fontem sablone CEZ) - jde o vlastnosti stylu jako
;;     celku, ne konkretniho textu, proto se u techto radku neuvadi souradnice,
;;  b) KONKRETNI entity TEXT/MTEXT, ktere pouzivaji nevyhovujici styl (chybejici
;;     v sablone, s jinym fontem, nebo primo styl STANDARD) - u techto radku UZ
;;     JE uvedeno kde ve vykresu se dany text nachazi (souradnice, hladina,
;;     handle) pres cez-entity-loc-str, aby slo misto snadno dohledat.
(defun cez-check-textstyles ( / tbl name font rec n-ok n-warn bad-styles ss i ent elist style n-usages maxlist shown)
  (cez-log "\n=== 3) KONTROLA TEXTOVYCH STYLU ===")
  (setq n-ok 0 n-warn 0 bad-styles '())
  (setq tbl (tblnext "STYLE" T))
  (while tbl
    (setq name (cdr (assoc 2 tbl))
          font (cdr (assoc 3 tbl)))
    (setq rec (cez-textstyle-lookup name))
    (cond
      ((= name "Standard")
        ;; Standard je vzdy pritomny v definici, ale dle VP C kap. 3.4.3.3 (drive
        ;; 3.4.5) se NESMI pouzivat pro skutecny text - viz entity-level kontrola
        ;; nize, ktera hlida jeho POUZITI, ne jen pritomnost v tabulce stylu.
        (setq n-ok (1+ n-ok))
        (setq bad-styles (cons "STANDARD" bad-styles))
      )
      ((null rec)
        (setq n-warn (1+ n-warn))
        (setq bad-styles (cons (strcase name) bad-styles))
        (cez-warn (strcat "Textovy styl '" name "' (font '" font "') neni v seznamu povolenych "
                           "stylu sablony CEZ. Dle CEZ_ST_0093 kap. 3.1.4/VP C se maji pouzivat "
                           "pisma dle ISO 3098 (isocp.shx / iso3098b.shx / isocpeur.ttf) nebo "
                           "vlastni pismo splnujici pozadavky VP C a VP X."))
      )
      ((/= (strcase font) (strcase (cdr rec)))
        (setq n-warn (1+ n-warn))
        (setq bad-styles (cons (strcase name) bad-styles))
        (cez-warn (strcat "Textovy styl '" name "' pouziva font '" font "', ocekavan '" (cdr rec) "'."))
      )
      (t (setq n-ok (1+ n-ok)))
    )
    (setq tbl (tblnext "STYLE"))
  )
  (cez-log (strcat "Shrnuti definic stylu: OK=" (itoa n-ok) ", odlisnych/neznamych=" (itoa n-warn)))

  ;; Entity-level dohledani KONKRETNICH textu pouzivajicich nevyhovujici styl
  (if bad-styles
    (progn
      (setq n-usages 0 maxlist 30 shown 0)
      (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT"))))
      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq ent (ssname ss i) elist (entget ent))
            (setq style (cdr (assoc 7 elist)))
            (if (and style (member (strcase style) bad-styles))
              (progn
                (setq n-usages (1+ n-usages))
                (if (< shown maxlist)
                  (progn
                    (cez-warn (strcat (cdr (assoc 0 elist)) " se stylem '" style
                                       "' nalezen na: " (cez-entity-loc-str ent)))
                    (setq shown (1+ shown))
                  )
                )
              )
            )
            (setq i (1+ i))
          )
        )
      )
      (cez-log (strcat "  Pocet konkretnich textu s nevyhovujicim stylem: " (itoa n-usages)
                        (if (>= shown maxlist) " (vypis omezen, viz soucet)" "")))
    )
  )
)

;; ----------------------------------------------------------------------
;; 4) Kontrola ramecku a popisoveho pole
;; ----------------------------------------------------------------------

;; Najde vsechny insert entity v modelu i vsech layoutech, jejichz jmeno bloku
;; (case-insensitive, bez diakritiky na vstupu) odpovida hledanemu retezci.
(defun cez-collect-inserts-by-name (names / ss i ent obj bname found result)
  (setq result '())
  (setq ss (ssget "_X" (list (cons 0 "INSERT"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq bname (cdr (assoc 2 (entget ent))))
        (if (member (strcase bname) (mapcar 'strcase names))
          (setq result (cons ent result))
        )
        (setq i (1+ i))
      )
    )
  )
  result
)

;; Precte atributy (ATTRIB) patrici k dane INSERT entite (primo nasledujici v DB)
(defun cez-read-attribs (ins-ent / e result tag val)
  (setq result '())
  (setq e (entnext ins-ent))
  (while (and e (= (cdr (assoc 0 (entget e))) "ATTRIB"))
    (setq tag (cdr (assoc 2 (entget e)))
          val (cdr (assoc 1 (entget e))))
    (setq result (cons (cons tag val) result))
    (setq e (entnext e))
  )
  result
)

(defun cez-attr-get (attrs tag / a)
  (setq a (assoc (strcase tag) (mapcar '(lambda (p) (cons (strcase (car p)) (cdr p))) attrs)))
  (if a (cdr a) nil)
)

;; Vrati T, pokud retezec s obsahuje jen cislice 0-9 a neni prazdny
(defun cez-digits-p (s / i ok c)
  (setq i 1 ok (> (strlen s) 0))
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (if (not (vl-string-search c "0123456789")) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

;; Vrati T, pokud retezec s obsahuje jen pismena A-Z (bez ohledu na velikost) a neni prazdny
(defun cez-alpha-p (s / i ok c)
  (setq i 1 ok (> (strlen s) 0))
  (while (and ok (<= i (strlen s)))
    (setq c (strcase (substr s i 1)))
    (if (not (vl-string-search c "ABCDEFGHIJKLMNOPQRSTUVWXYZ")) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

(defun cez-lokalita-edu-p (lok) (member lok (list "EDU" "JE Dukovany" "Dukovany")))
(defun cez-lokalita-ete-p (lok) (member lok (list "ETE" "JE Temel\U+00EDn" "Temel\U+00EDn" "JE Temelin" "Temelin")))

;; Zname priklady kodu TYP dle VP C kap. 5.1.1 (neni to nutne uplny seznam - plny
;; ciselnik je ve volne priloze A, kterou nemame k dispozici)
(setq *cez-typ-priklady* (list "H16T" "H16S" "PPPt" "PPPs" "H01T" "H01S" "EDST" "EDSS"))

(defun cez-check-titleblock (fix-p / ramecek-list pole-list ins attrs archc lokalita nazev1 ktd stupen cislo-akce datum
                              archc-clean n-problems val pair so-dps typ-val bname pole-plne-p povinna-pole e-archc)
  (cez-log "\n=== 4) KONTROLA RAMECKU A POPISOVEHO POLE ===")
  (setq ramecek-list (cez-collect-inserts-by-name (list "Ramecek" "R\U+00E1me\U+010Dek" "A0" "A0-1" "A0-2" "A1" "A1.0" "A1-2"
                                                          "A1-3" "A1-4" "A2" "A2.0" "A2.1" "A2-3" "A2-4" "A2-5" "A2-6"
                                                          "A3" "A3.0" "A3.1" "A3.2" "A3-5" "A3-6" "A3-7" "A3-8" "A3-9"
                                                          "A3-10" "A4" "TL-A3" "TL-A4")))
  (if (null ramecek-list)
    (cez-warn "Ve vykresu nebyl nalezen blok RAMECEK (formatovy blok A0-A4/TL-A3/TL-A4) dle sablony CEZ. Zkontroluj, zda je vykres zalozen na sablone CEZ_Sablona vykresu podla VPC_REV2.dwt.")
    (cez-ok (strcat "Nalezeno vlozeni ramecku/formatu: " (itoa (length ramecek-list)) "x."))
  )

  (setq pole-list (cez-collect-inserts-by-name *cez-bloky-pole*))
  (if (null pole-list)
    (progn
      (cez-warn "Ve vykresu nebyl nalezen blok popisoveho pole (Pole-1r/Pole-1z/Pole-2/Pole-3).")
      (cez-warn "Bez popisoveho pole nelze zkontrolovat dodavatelske cislo, lokalitu, nazev dokumentu apod. dle kap. 3.1.4-3.1.6 CEZ_ST_0093.")
    )
    (progn
      (cez-ok (strcat "Nalezeno vlozeni popisoveho pole: " (itoa (length pole-list)) "x. Kontroluji obsah..."))
      (foreach ins pole-list
        (setq attrs (cez-read-attribs ins))
        (setq n-problems 0)
        ;; Zjisti typ popisoveho pole - dle VP C (Zasady provedeni dokumentu,
        ;; Vicelisty dokument) se PLNE popisove pole (vsechny udaje) pouziva
        ;; JEN na titulnim listu (bloky Pole-1r/Pole-1z). Na dalsich listech
        ;; se pouziva jen zjednoduseny blok Pole-2/Pole-3, ktery STRUKTURALNE
        ;; neobsahuje atributy jako CISLO_AKCE, STUPEN_PD, SO_DPS, DATUM,
        ;; TYP/PODTYP, POR_C, MERITKO, SCHVALIL apod. - to je ZAMER metodiky,
        ;; ne chyba vykresu. Kontrola proto tyto atributy vyzaduje jen na
        ;; Pole-1r/Pole-1z, u Pole-2/Pole-3 se rovnou preskakuji.
        (setq bname (strcase (cdr (assoc 2 (entget ins)))))
        (setq pole-plne-p (member bname (list "POLE-1R" "POLE-1Z")))
        (cez-log (strcat "  -- popisove pole (" bname ", "
                          (if pole-plne-p "titulni list, plne pole" "pokracovaci list, zjednodusene pole")
                          ") nalezeno na: " (cez-entity-loc-str ins) " --"))

        ;; ARCH_C - dodavatelske cislo: max 15 znaku, jen A-Z 0-9 - / .
        (setq archc (cez-attr-get attrs "ARCH_C"))
        (cond
          ((or (null archc) (= (cez-str-nospace archc) ""))
            (setq n-problems (1+ n-problems))
            (cez-warn "Pole ARCH_C (dodavatelske/archivni cislo) je prazdne."))
          (t
            (setq archc-clean (cez-str-nospace (cez-str-upper archc)))
            (cond
              ((> (strlen archc-clean) 15)
                (setq n-problems (1+ n-problems))
                (cez-warn (strcat "Dodavatelske cislo '" archc "' ma po ocisteni " (itoa (strlen archc-clean))
                                   " znaku (max. 15 dle kap. 3.1.4 CEZ_ST_0093). Zkrat rucne dle pravidel standardu.")))
              ((not (cez-chars-ok-p archc-clean *cez-arch-c-ok*))
                (setq n-problems (1+ n-problems))
                (cez-warn (strcat "Dodavatelske cislo '" archc "' obsahuje nepovolene znaky "
                                   "(povoleno jen A-Z, 0-9, -, /, . dle kap. 3.1.4).")))
              ((/= archc archc-clean)
                (if fix-p
                  (progn
                    (setq e-archc (cez-find-attrib-ent ins "ARCH_C"))
                    (entmod (subst (cons 1 archc-clean) (cons 1 archc) (entget e-archc)))
                    (entupd e-archc)
                    (cez-fix (strcat "ARCH_C '" archc "' -> '" archc-clean "' (velka pismena, bez mezer)."))
                  )
                  (cez-warn (strcat "Dodavatelske cislo '" archc "' by melo byt '" archc-clean
                                     "' (velka pismena bez mezer) - spust CEZ-OPRAVA pro automatickou opravu."))
                )
              )
              (t (cez-ok (strcat "ARCH_C = '" archc "' OK.")))
            )
          )
        )

        ;; LOKALITA
        (setq lokalita (cez-attr-get attrs "LOKALITA"))
        (if lokalita
          (if (member lokalita *cez-lokality*)
            (cez-ok (strcat "LOKALITA = '" lokalita "' OK."))
            (progn (setq n-problems (1+ n-problems))
                   (cez-warn (strcat "LOKALITA = '" lokalita "' neodpovida povolenym hodnotam "
                                      "(EDU/JE Dukovany/Dukovany/ETE/JE Temelin/Temelin) dle kap. 3.1.3.")))
          )
        )

        ;; Povinna pole - jen kontrola prazdnoty. Rozsah povinnych poli zavisi
        ;; na typu bloku (viz pole-plne-p vyse): CISLO_AKCE a STUPEN_PD
        ;; strukturalne existuji jen v Pole-1r/Pole-1z (titulni list) - na
        ;; Pole-2/Pole-3 (pokracovaci listy) je VP C vubec nevyzaduje/
        ;; neobsahuje, proto se tam nekontroluji (byla by to falesna chyba).
        (setq povinna-pole
          (if pole-plne-p
            (list (cons "NAZEV_1" "Nazev vykresu") (cons "KTD" "Kod tridy dokumentu")
                  (cons "\U+010CISLO_AKCE" "Cislo akce") (cons "STUPE\U+0147_PD" "Stupen PD")
                  (cons "VYPRACOVAL" "Vypracoval"))
            (list (cons "NAZEV_1" "Nazev vykresu") (cons "KTD" "Kod tridy dokumentu")
                  (cons "VYPRACOVAL" "Vypracoval"))
          )
        )
        (foreach pair povinna-pole
          (setq val (cez-attr-get attrs (car pair)))
          (if (or (null val) (= (cez-str-nospace val) ""))
            (progn (setq n-problems (1+ n-problems))
                   (cez-warn (strcat "Pole '" (car pair) "' (" (cdr pair) ") je prazdne.")))
          )
        )

        ;; Nasledujici atributy (DATUM, SO_DPS, CISLO_AKCE, TYP) STRUKTURALNE
        ;; existuji jen v blocich Pole-1r/Pole-1z (titulni list) - VP C je na
        ;; Pole-2/Pole-3 (pokracovaci listy) vubec nepredepisuje/neobsahuje,
        ;; proto se kontroluji jen kdyz pole-plne-p je pravda.
        (if pole-plne-p
          (progn
            ;; DATUM - format dd.mm.rrrr
            (setq datum (cez-attr-get attrs "DATUM"))
            (if (and datum (/= datum ""))
              (if (wcmatch datum "##.##.####")
                (cez-ok (strcat "DATUM = '" datum "' OK."))
                (progn (setq n-problems (1+ n-problems))
                       (cez-warn (strcat "DATUM = '" datum "' neodpovida formatu dd.mm.rrrr.")))
              )
            )

            ;; SO_DPS - max. 12 znaku dle VP C kap. 5.1.1
            (setq so-dps (cez-attr-get attrs "SO_DPS"))
            (if (and so-dps (> (strlen so-dps) 12))
              (progn (setq n-problems (1+ n-problems))
                     (cez-warn (strcat "Pole SO_DPS = '" so-dps "' ma " (itoa (strlen so-dps))
                                        " znaku, max. povoleno je 12 (VP C kap. 5.1.1).")))
            )

            ;; Cislo akce - format zavisi na lokalite (VP C kap. 5.1.1):
            ;; EDU = ctyrmistne cislo (napr. 7709), ETE = pismeno + trimistne cislo (napr. B633)
            (setq cislo-akce (cez-attr-get attrs "\U+010CISLO_AKCE"))
            (if (and cislo-akce (/= cislo-akce "") lokalita)
              (cond
                ((cez-lokalita-edu-p lokalita)
                  (if (and (= (strlen cislo-akce) 4) (cez-digits-p cislo-akce))
                    (cez-ok (strcat "\U+010CISLO_AKCE = '" cislo-akce "' OK (EDU, ctyrmistne cislo)."))
                    (progn (setq n-problems (1+ n-problems))
                           (cez-warn (strcat "\U+010CISLO_AKCE = '" cislo-akce "' neodpovida formatu pro EDU "
                                              "(ma byt ctyrmistne cislo, napr. 7709) dle VP C kap. 5.1.1.")))
                  )
                )
                ((cez-lokalita-ete-p lokalita)
                  (if (and (= (strlen cislo-akce) 4) (cez-alpha-p (substr cislo-akce 1 1))
                           (cez-digits-p (substr cislo-akce 2 3)))
                    (cez-ok (strcat "\U+010CISLO_AKCE = '" cislo-akce "' OK (ETE, pismeno+trimistne cislo)."))
                    (progn (setq n-problems (1+ n-problems))
                           (cez-warn (strcat "\U+010CISLO_AKCE = '" cislo-akce "' neodpovida formatu pro ETE "
                                              "(ma byt 1 pismeno + trimistne cislo, napr. B633) dle VP C kap. 5.1.1.")))
                  )
                )
              )
            )

            ;; TYP - jen informativni porovnani se znamymi priklady z VP C kap. 5.1.1
            (setq typ-val (cez-attr-get attrs "TYP"))
            (if (and typ-val (/= typ-val "") (not (member typ-val *cez-typ-priklady*)))
              (cez-log (strcat "  [INFO]   Pole TYP = '" typ-val "' neni v prikladech VP C kap. 5.1.1 "
                                "(H16T/H16S/PPPt/PPPs/H01T/H01S/EDST/EDSS) - overit rucne proti volne priloze A "
                                "(plny ciselnik typu nemam k dispozici)."))
            )
          )
        )

        ;; KTD - kod tridy dokumentu: 4 znaky, velka pismena/cislice (napr. DD04, EC05).
        ;; Existuje na VSECH ctyrech blocich (Pole-1r/1z i Pole-2/3), kontroluje se vzdy.
        (setq ktd (cez-attr-get attrs "KTD"))
        (if (and ktd (/= ktd ""))
          (if (= (strlen ktd) 4)
            (cez-ok (strcat "KTD = '" ktd "' ma spravnou delku (4 znaky)."))
            (progn (setq n-problems (1+ n-problems))
                   (cez-warn (strcat "KTD = '" ktd "' nema 4 znaky, jak predepisuje VP A/VP C "
                                      "(napr. DD04, EC05, QC29).")))
          )
        )

        (if (= n-problems 0) (cez-ok "Popisove pole bez zjistenych problemu."))
      )
    )
  )
)

;; Najde ATTRIB entitu s danym tagem patrici k INSERT entite ins
(defun cez-find-attrib-ent (ins-ent tag / e)
  (setq e (entnext ins-ent))
  (while (and e (= (cdr (assoc 0 (entget e))) "ATTRIB") (/= (strcase (cdr (assoc 2 (entget e)))) (strcase tag)))
    (setq e (entnext e))
  )
  (if (and e (= (cdr (assoc 0 (entget e))) "ATTRIB")) e nil)
)

;; ----------------------------------------------------------------------
;; 5) Kontrola barev, carovych typu a tloustek car PRIMO NA ENTITACH
;;    (override proti ByLayer)
;;
;; CEZ metodika (viz sablona + CTB "cez_dje-ctb.ctb") priradi tloustku
;; care pri tisku podle BARVY objektu (Color-Dependent Plot Style Table),
;; nikoli podle nazvu hladiny. Pokud ma entita barvu nastavenou primo
;; (ne "ByLayer"), pri tisku dostane tloustku podle teto barvy misto podle
;; barvy predepsane pro danou hladinu - vysledny vykres pak neodpovida
;; metodice, i kdyz hladiny same jsou v poradku.
;;
;; VYJIMKA (CEZ_ST_0093r06 kap. 3.6.3): zmeny v "Red correct"/DoSP-ZKZ se
;; smeji odlisovat barevne umyslne ("zakres zmen graficky odlisen od
;; puvodniho provedeni, napr. barevne nebo podbarvenim"). Barevny override
;; proto NENI automaticky opravovan (mohl by smazat legitimni oznaceni
;; revize) - pouze se nahlasi k rucnimu posouzeni.
;;
;; Carovy typ a tloustka cary (lineweight) nastavene primo na entite naopak
;; s oznacovanim revizi dle standardu nesouvisi - ty se pri CEZ-OPRAVA
;; bezpecne prevadeji zpet na ByLayer.
;; ----------------------------------------------------------------------

;; Vrati citelny popis "kde ve vykresu" se entita nachazi - souradnice
;; reprezentativniho bodu (insercni/pocatecni/stredovy bod, DXF kod 10),
;; hladina a prostor (Model / Papir - rozvrzeni). Pouziva se ve varovnych
;; hlaskach, aby bylo mozne entitu snadno dohledat (napr. prikazem
;; AutoCADu "ID" na dane souradnice, nebo filtrem podle handle).
(defun cez-entity-loc-str (ent / elist pt spc lay handle)
  (setq elist (entget ent))
  (setq pt (cdr (assoc 10 elist)))
  (setq lay (cdr (assoc 8 elist)))
  (setq handle (cdr (assoc 5 elist)))
  (setq spc (if (= (cdr (assoc 67 elist)) 1) "Papir/rozvrzeni" "Model"))
  (strcat
    (if pt
      (strcat "X=" (rtos (car pt) 2 2) " Y=" (rtos (cadr pt) 2 2))
      "souradnice neznamy"
    )
    ", prostor=" spc
    (if lay (strcat ", hladina='" lay "'") "")
    ", handle=" (if handle handle "?")
  )
)

;; Vrati kratky nahled textoveho obsahu entity (DXF kod 1) pro TEXT/MTEXT,
;; oriznuty na max. 40 znaku, aby se dal text ve varovani snadno poznat.
(defun cez-text-preview (elist / txt)
  (setq txt (cdr (assoc 1 elist)))
  (cond
    ((null txt) "")
    ((> (strlen txt) 40) (strcat (substr txt 1 40) "..."))
    (t txt)
  )
)

(defun cez-aci-name (n)
  (cond
    ((= n 1) "1-cervena") ((= n 2) "2-zluta") ((= n 3) "3-zelena")
    ((= n 4) "4-azurova") ((= n 5) "5-modra") ((= n 6) "6-purpurova")
    ((= n 7) "7-bila/cerna") ((= n 8) "8-tmave siva") ((= n 9) "9-svetle siva")
    (t (itoa n))
  )
)

;; Nastavi/prepise DXF kod v entite na novou hodnotu (pripadne kod prida, pokud chybi)
(defun cez-set-dxf (ent code newval / elist pair)
  (setq elist (entget ent))
  (setq pair (assoc code elist))
  (if pair
    (entmod (subst (cons code newval) pair elist))
    (entmod (append elist (list (cons code newval))))
  )
)

(defun cez-check-entity-colors (fix-p / ss i ent elist etype pair-c pair-lt pair-lw col lt lw layer
                                 n-total n-color n-byblock n-lt n-lw n-lt-fixed n-lw-fixed maxlist shown)
  (cez-log "\n=== 5) KONTROLA BAREV, CAROVYCH TYPU A TLOUSTEK NA ENTITACH (override proti ByLayer) ===")
  (setq n-total 0 n-color 0 n-byblock 0 n-lt 0 n-lw 0 n-lt-fixed 0 n-lw-fixed 0 maxlist 40 shown 0)
  (setq ss (ssget "_X"))
  (if (not ss)
    (cez-log "  Ve vykresu nejsou zadne entity k prohledani.")
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq elist (entget ent))
        (setq etype (cdr (assoc 0 elist)))
        ;; preskocit netisknutelne/pomocne objekty (ATTRIB se kontroluje take - viditelne
        ;; vyplnene atributy v blocich maji vlastni tisknutelnou barvu jako kterakoli entita)
        (if (not (member etype (list "ATTDEF" "VIEWPORT")))
          (progn
            (setq n-total (1+ n-total))
            (setq layer (cdr (assoc 8 elist)))

            ;; --- barva ---
            (setq pair-c (assoc 62 elist))
            (if pair-c
              (progn
                (setq col (cdr pair-c))
                (cond
                  ((= col 0)
                    (setq n-byblock (1+ n-byblock))
                    (if (< shown maxlist)
                      (progn (cez-warn (strcat "Entita " etype " ma barvu ByBlock misto ByLayer. Nalezeno na: "
                                                 (cez-entity-loc-str ent)))
                             (setq shown (1+ shown)))
                    )
                  )
                  ((= col 2)
                    (setq n-color (1+ n-color))
                    (if (< shown maxlist)
                      (progn (cez-warn (strcat "Entita " etype " ma barvu 2-zluta primo na entite. "
                                                 "VP C kap. 3.4.4: zluta (255,255,0) a podobne svetle odstiny "
                                                 "jsou VYSLOVNE ZAKAZANY na bilem podkladu tiskoveho vystupu - "
                                                 "i mezi barvami 1-9, ktere si jinak pri tisku zachovavaji "
                                                 "vlastni barvu. Nalezeno na: " (cez-entity-loc-str ent)))
                             (setq shown (1+ shown)))
                    )
                  )
                  (t
                    (setq n-color (1+ n-color))
                    (if (< shown maxlist)
                      (progn (cez-warn (strcat "Entita " etype " ma primo nastavenou barvu "
                                                 (cez-aci-name col) " misto ByLayer. Dle VP C kap. 3.4.4: barvy "
                                                 "1-9 si pri tisku zachovaji vlastni barvu (pro barevny vykres), "
                                                 "barvy 10-254 se tisknou cerne (krome 103=maskovaci bila a "
                                                 "254=seda pro bourane konstrukce). Pokud tomu barva na teto "
                                                 "entite neodpovida, nebo jde o zamerne barevne oznaceni revize "
                                                 "(kap. 3.6.3 CEZ_ST_0093), posud rucne. Nalezeno na: "
                                                 (cez-entity-loc-str ent)))
                             (setq shown (1+ shown)))
                    )
                  )
                )
              )
            )

            ;; --- carovy typ ---
            (setq pair-lt (assoc 6 elist))
            (if (and pair-lt (not (member (strcase (cdr pair-lt)) (list "BYLAYER" "BYBLOCK"))))
              (progn
                (setq n-lt (1+ n-lt))
                (if (< shown maxlist)
                  (progn (cez-warn (strcat "Entita " etype " ma primo nastaveny carovy typ '"
                                             (cdr pair-lt) "' misto ByLayer. Nalezeno na: "
                                             (cez-entity-loc-str ent)))
                         (setq shown (1+ shown)))
                )
                (if fix-p
                  (progn (cez-set-dxf ent 6 "ByLayer") (setq n-lt-fixed (1+ n-lt-fixed)))
                )
              )
            )

            ;; --- tloustka cary (lineweight) ---
            (setq pair-lw (assoc 370 elist))
            (if (and pair-lw (not (member (cdr pair-lw) (list -1 -2))))
              (progn
                (setq n-lw (1+ n-lw))
                (if (< shown maxlist)
                  (progn (cez-warn (strcat "Entita " etype " ma primo nastavenou tloustku cary ("
                                             (itoa (cdr pair-lw)) ") misto ByLayer. Nalezeno na: "
                                             (cez-entity-loc-str ent)))
                         (setq shown (1+ shown)))
                )
                (if fix-p
                  (progn (cez-set-dxf ent 370 -1) (setq n-lw-fixed (1+ n-lw-fixed)))
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
      (if (>= shown maxlist)
        (cez-log (strcat "  (vypis jednotlivych radku omezen na " (itoa maxlist) ", zbytek jen v souctech nize)"))
      )
    )
  )
  (cez-log (strcat "Shrnuti (z " (itoa n-total) " entit): "
                    "barva primo=" (itoa n-color)
                    ", barva ByBlock=" (itoa n-byblock)
                    ", carovy typ primo=" (itoa n-lt) (if fix-p (strcat " (opraveno " (itoa n-lt-fixed) ")") "")
                    ", tloustka cary primo=" (itoa n-lw) (if fix-p (strcat " (opraveno " (itoa n-lw-fixed) ")") "")))
  (if (> n-color 0)
    (cez-log "  POZNAMKA: primo nastavene barvy se NEOPRAVUJI automaticky - mohou oznacovat revize (kap. 3.6.3). Posud rucne.")
  )
)

;; Doplnkova (souhrnna, ne polozkova) kontrola barev/carovych typu/tloustek
;; NASTAVENYCH PRIMO NA ENTITACH ULOZENYCH UVNITR DEFINIC BLOKU. cez-check-
;; entity-colors vyse prochazi jen ssget "_X" (model/rozvrzeni), coz entity
;; uvnitr definice bloku vubec nevidi - proto se blok se "zapecenou" barvou v
;; definici (napr. barevny symbol z knihovny) v puvodni kontrole vubec
;; neobjevi, i kdyz jeho vysledna barva pri tisku muze byt take spatne.
(defun cez-check-block-def-colors ( / tbl bname btype bstart e elist n-blocks n-color n-lt n-lw pair
                                     bad-blocks b-color b-lt b-lw ins-ss)
  (cez-log "\n=== 5b) BARVY/CAROVE TYPY/TLOUSTKY UVNITR DEFINIC BLOKU ===")
  (setq n-blocks 0 n-color 0 n-lt 0 n-lw 0 bad-blocks '())
  (setq tbl (tblnext "BLOCK" T))
  (while tbl
    (setq bname (cdr (assoc 2 tbl)))
    (setq btype (cdr (assoc 70 tbl)))
    (if (and (/= (substr bname 1 1) "*")
             (not (and btype (/= 0 (logand btype 12)))))
      (progn
        (setq b-color 0 b-lt 0 b-lw 0)
        (setq bstart (tblobjname "BLOCK" bname))
        (setq e (entnext bstart))
        (while e
          (setq elist (entget e))
          (if (assoc 62 elist) (setq b-color (1+ b-color)))
          (setq pair (assoc 6 elist))
          (if (and pair (not (member (strcase (cdr pair)) (list "BYLAYER" "BYBLOCK"))))
            (setq b-lt (1+ b-lt))
          )
          (setq pair (assoc 370 elist))
          (if (and pair (not (member (cdr pair) (list -1 -2))))
            (setq b-lw (1+ b-lw))
          )
          (setq e (entnext e))
        )
        (setq n-blocks (1+ n-blocks) n-color (+ n-color b-color) n-lt (+ n-lt b-lt) n-lw (+ n-lw b-lw))
        (if (or (> b-color 0) (> b-lt 0) (> b-lw 0))
          (setq bad-blocks (cons (list bname b-color b-lt b-lw) bad-blocks))
        )
      )
    )
    (setq tbl (tblnext "BLOCK"))
  )
  (cez-log (strcat "Shrnuti (prohledano " (itoa n-blocks) " definic bloku): entit s barvou primo/ByBlock="
                    (itoa n-color) ", s carovym typem primo=" (itoa n-lt) ", s tloustkou primo=" (itoa n-lw)))
  (if bad-blocks
    (progn
      (cez-log (strcat "  POZNAMKA: toto jsou souctove pocty uvnitr DEFINIC bloku (ne jednotlive vypisy jako "
                        "u sekce 5). Prime barvy 1-9 lze hromadne prevest v CEZ-OPRAVA (dotaz v sekci 7b), "
                        "ktery je prevadi i uvnitr definic bloku."))
      (cez-log "  Dotcene bloky (nazev: pocet entit s primou barvou/carovym typem/tloustkou, pocet vlozeni a priklad umisteni prvniho vlozeni):")
      (foreach bb bad-blocks
        (setq bname (car bb))
        (setq ins-ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 bname))))
        (cez-log (strcat "    - '" bname "': barva=" (itoa (cadr bb)) ", carovy typ=" (itoa (caddr bb))
                          ", tloustka=" (itoa (cadddr bb)) ", vlozeno v modelu/rozvrzeni "
                          (if ins-ss (itoa (sslength ins-ss)) "0") "x"
                          (if (and ins-ss (> (sslength ins-ss) 0))
                            (strcat ", 1. vyskyt na: " (cez-entity-loc-str (ssname ins-ss 0)))
                            ""
                          )))
      )
    )
  )
)

;; ----------------------------------------------------------------------
;; 6) Dalsi kontroly dle VOLNE PRILOHY C (Pozadavky na vykres)
;; ----------------------------------------------------------------------

;; --- 6a) Kodova stranka vykresu musi byt ANSI_1250 (cestina) - VP C kap. 3.4.5 ---
(defun cez-check-codepage (fix-p / cp)
  (cez-log "\n=== 6a) KODOVA STRANKA VYKRESU ===")
  (setq cp (getvar "DWGCODEPAGE"))
  (if (= (strcase cp) "ANSI_1250")
    (cez-ok (strcat "DWGCODEPAGE = '" cp "' OK."))
    (progn
      (cez-warn (strcat "DWGCODEPAGE = '" cp "', ma byt 'ANSI_1250' (cestina) dle VP C kap. 3.4.5."))
      (if fix-p
        (progn (setvar "DWGCODEPAGE" "ANSI_1250") (cez-fix "DWGCODEPAGE nastaveno na ANSI_1250."))
      )
    )
  )
)

;; --- 6b) Kresleni v hladine "0" je zakazano - VP C kap. 3.4 ---
(defun cez-check-layer-zero ( / ss i ent elist etype n-total n-bad shown maxlist)
  (cez-log "\n=== 6b) KRESLENI V HLADINE \"0\" (zakazano dle VP C) ===")
  (setq n-total 0 n-bad 0 shown 0 maxlist 30)
  (setq ss (ssget "_X"))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) elist (entget ent) etype (cdr (assoc 0 elist)))
        (if (and (not (member etype (list "ATTDEF" "ATTRIB" "VIEWPORT")))
                 (= (cdr (assoc 8 elist)) "0"))
          (progn
            (setq n-bad (1+ n-bad))
            (if (< shown maxlist)
              (progn (cez-warn (strcat "Entita " etype " je nakreslena primo v hladine \"0\" - VP C: "
                                         "\"Je nepripustne kreslit v hladine 0.\" Preskup ji na "
                                         "prislusnou hladinu z Knihovny AutoCAD DJE. Nalezeno na: "
                                         (cez-entity-loc-str ent)))
                     (setq shown (1+ shown)))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (cez-log (strcat "Shrnuti: entit v hladine 0 = " (itoa n-bad)
                    (if (>= shown maxlist) " (vypis omezen, viz soucet)" "")))
)

;; --- 6c) Externi reference (XREF) a proxy grafika jsou zakazany - VP C kap. 3.4 ---
(defun cez-check-xref-proxy ( / tbl name flags n-xref ss)
  (cez-log "\n=== 6c) EXTERNI REFERENCE A PROXY GRAFIKA (zakazano dle VP C) ===")
  (setq n-xref 0)
  (setq tbl (tblnext "BLOCK" T))
  (while tbl
    (setq name (cdr (assoc 2 tbl)) flags (cdr (assoc 70 tbl)))
    (if (and flags (= (logand flags 4) 4))
      (progn (setq n-xref (1+ n-xref))
             (cez-warn (strcat "Blok '" name "' je externi reference (XREF). VP C: "
                                "\"DWG vykres nesmi obsahovat externi reference a proxy grafiku.\" "
                                "Pripoj (BIND) nebo nahrad statickym blokem.")))
    )
    (setq tbl (tblnext "BLOCK"))
  )
  (if (= n-xref 0) (cez-ok "Ve vykresu nejsou zadne externi reference (XREF)."))

  (setq ss (ssget "_X" (list (cons 0 "ACAD_PROXY_ENTITY"))))
  (if ss
    (cez-warn (strcat "Ve vykresu je nalezeno " (itoa (sslength ss)) "x proxy grafiky (ACAD_PROXY_ENTITY). "
                       "VP C zakazuje proxy grafiku - obvykle vznika chybejicim ObjectARX modulem/aplikaci, "
                       "kterou pouzil autor vykresu. Zkontroluj zdroj a nahrad standardni geometrii."))
    (cez-ok "Ve vykresu neni zadna proxy grafika.")
  )
)

;; --- 6d) Textovy styl STANDARD nesmi byt pouzivan - VP C kap. 3.4.5 ---
;;     Vyska pisma musi byt z povolene rady (mm) - VP C kap. 3.4.5
;;     Text nesmi byt zrcadleny (obracene/vzhuru nohama) - VP C kap. 3.4.5
(setq *cez-vyska-pisma-mm* (list 10.0 7.0 5.0 3.5 3.0 2.5 2.0 1.8))

(defun cez-height-allowed-p (h / v ok)
  (setq ok nil)
  (foreach v *cez-vyska-pisma-mm*
    (if (< (abs (- h v)) 0.01) (setq ok T))
  )
  ok
)

(defun cez-check-text-rules ( / ss i ent elist style height flags n-standard n-height n-mirror shown maxlist n-total)
  (cez-log "\n=== 6d) TEXTOVE STYLY A VYSKY PISMA NA ENTITACH TEXT ===")
  (setq n-standard 0 n-height 0 n-mirror 0 shown 0 maxlist 30 n-total 0)
  (setq ss (ssget "_X" (list (cons 0 "TEXT"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) elist (entget ent))
        (setq n-total (1+ n-total))
        (setq style (cdr (assoc 7 elist)))
        (setq height (cdr (assoc 40 elist)))
        (setq flags (cdr (assoc 71 elist)))
        (if (and style (= (strcase style) "STANDARD"))
          (progn (setq n-standard (1+ n-standard))
                 (if (< shown maxlist)
                   (progn (cez-warn (strcat "TEXT '" (cez-text-preview elist) "' pouziva styl STANDARD - "
                                              "VP C kap. 3.4.5: \"Styl pisma STANDARD nesmi byt pouzivan.\" "
                                              "Pouzij nektery ze stylu rady ISO 3098. Nalezeno na: "
                                              (cez-entity-loc-str ent)))
                          (setq shown (1+ shown)))
                 )
          )
        )
        (if (and height (> height 0.0) (not (cez-height-allowed-p height)))
          (progn (setq n-height (1+ n-height))
                 (if (< shown maxlist)
                   (progn (cez-warn (strcat "TEXT '" (cez-text-preview elist) "' ma vysku " (rtos height 2 2)
                                              " mm, coz neni v povolene rade dle VP C kap. 3.4.5 "
                                              "(10; 7; 5; 3,5; 3; 2,5; 2; 1,8 mm). Nalezeno na: "
                                              (cez-entity-loc-str ent)))
                          (setq shown (1+ shown)))
                 )
          )
        )
        (if (and flags (/= (logand flags 6) 0))
          (progn (setq n-mirror (1+ n-mirror))
                 (if (< shown maxlist)
                   (progn (cez-warn (strcat "TEXT '" (cez-text-preview elist) "' je "
                                              (cond ((= (logand flags 6) 6) "obracene a vzhuru nohama")
                                                    ((= (logand flags 2) 2) "napsano obracene (zrcadlove)")
                                                    (t "napsano vzhuru nohama"))
                                              " - VP C kap. 3.4.5: \"Nebudou pouzivana pisma obracena, "
                                              "psana opacne...\" Nalezeno na: " (cez-entity-loc-str ent)))
                          (setq shown (1+ shown)))
                 )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (cez-log (strcat "Shrnuti (z " (itoa n-total) " TEXT entit): styl STANDARD=" (itoa n-standard)
                    ", nepovolena vyska=" (itoa n-height) ", zrcadleny/obraceny=" (itoa n-mirror)))
)

;; --- 6e) Kotovaci styl by nemel byt Standard/Annotative - VP C kap. 3.4.6 (CSN EN ISO 129-1) ---
(defun cez-check-dimstyle-usage ( / ss i ent elist dimstyle n-bad n-total shown maxlist)
  (cez-log "\n=== 6e) KOTOVACI STYL (DIMENSION) ===")
  (setq n-bad 0 n-total 0 shown 0 maxlist 20)
  (setq ss (ssget "_X" (list (cons 0 "DIMENSION"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) elist (entget ent))
        (setq n-total (1+ n-total))
        (setq dimstyle (cdr (assoc 3 elist)))
        (if (and dimstyle (member (strcase dimstyle) (list "STANDARD" "ANNOTATIVE")))
          (progn (setq n-bad (1+ n-bad))
                 (if (< shown maxlist)
                   (progn (cez-warn (strcat "DIMENSION pouziva kotovaci styl '" dimstyle "'. VP C kap. 3.4.6 "
                                              "vyzaduje soulad s CSN EN ISO 129-1 - pouzij styl ISO_129-1 "
                                              "(nebo ISO-25) ze sablony. Nalezeno na: " (cez-entity-loc-str ent)))
                          (setq shown (1+ shown)))
                 )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (if (= n-total 0)
    (cez-log "  Ve vykresu nejsou zadne kotovaci entity (DIMENSION).")
    (cez-log (strcat "Shrnuti (z " (itoa n-total) " kot): nevhodny styl=" (itoa n-bad)))
  )
)

;; --- 6f) CAD blok REVIZE a nazev hladiny REVIZE_xx - VP C kap. 3.5.1 ---
(defun cez-check-revize ( / revize-inserts ins attrs idx rusene layer-names tbl)
  (cez-log "\n=== 6f) BLOK REVIZE A HLADINA REVIZE_xx ===")
  (setq revize-inserts (cez-collect-inserts-by-name (list "REVIZE")))
  (if (null revize-inserts)
    (cez-log "  Ve vykresu nejsou zadne bloky REVIZE (zadna revize obsazena oblackem).")
    (progn
      (setq layer-names '())
      (setq tbl (tblnext "LAYER" T))
      (while tbl
        (setq layer-names (cons (cdr (assoc 2 tbl)) layer-names))
        (setq tbl (tblnext "LAYER"))
      )
      (foreach ins revize-inserts
        (setq attrs (cez-read-attribs ins))
        (setq idx (cez-attr-get attrs "OZNACENI_INDEX"))
        (setq rusene (cez-attr-get attrs "RUSENE_POZICE"))
        (cond
          ((or (null idx) (= idx "") (= idx "index"))
            (cez-warn (strcat "Blok REVIZE ma prazdny/nevyplneny atribut OZNACENI_INDEX. Nalezeno na: "
                               (cez-entity-loc-str ins))))
          (t
            (if (member (strcase idx) (list "CH" "O" "X"))
              (cez-warn (strcat "Blok REVIZE ma OZNACENI_INDEX = '" idx "', coz je zakazane pismeno "
                                 "(ch, o, x jsou dle CEZ_ST_0093r06 kap. 3.4.1.3 zakazana pro index zmeny). "
                                 "Nalezeno na: " (cez-entity-loc-str ins)))
            )
            (if (not (member (strcase (strcat "REVIZE_" idx)) (mapcar 'strcase layer-names)))
              (cez-warn (strcat "Blok REVIZE ma OZNACENI_INDEX = '" idx "', ale ve vykresu chybi odpovidajici "
                                 "hladina 'REVIZE_" idx "' (VP C kap. 3.5.1: revizni oblacek se kresli v nove "
                                 "hladine pojmenovane cislem revize s prefixem REVIZE_). Nalezeno na: "
                                 (cez-entity-loc-str ins)))
              (cez-ok (strcat "Blok REVIZE: OZNACENI_INDEX='" idx "' ma odpovidajici hladinu REVIZE_" idx "."))
            )
          )
        )
      )
    )
  )
)

;; --- 6g) CAD blok OZNACENI - SKRYTE_OZNACENI nesmi obsahovat mezery - VP C kap. 3.7 ---
(defun cez-check-oznaceni (fix-p / oznaceni-inserts ins attrs skryte vypsane n-total n-bad e-skryte skryte-clean)
  (cez-log "\n=== 6g) CAD BLOK OZNA\U+010CEN\U+00CD (znaceni projektovych pozic) ===")
  (setq oznaceni-inserts (cez-collect-inserts-by-name (list "OZNA\U+010CEN\U+00CD")))
  (setq n-total (length oznaceni-inserts) n-bad 0)
  (if (= n-total 0)
    (cez-log "  Ve vykresu nejsou zadne bloky OZNA\U+010CEN\U+00CD.")
    (progn
      (foreach ins oznaceni-inserts
        (setq attrs (cez-read-attribs ins))
        (setq skryte (cez-attr-get attrs "SKRYTE_OZNACENI"))
        (setq vypsane (cez-attr-get attrs "VYPSANE_OZNACENI"))
        (if (and skryte (/= skryte "") (/= skryte (cez-str-nospace skryte)))
          (progn
            (setq n-bad (1+ n-bad))
            (setq skryte-clean (cez-str-nospace skryte))
            (if fix-p
              (progn
                (setq e-skryte (cez-find-attrib-ent ins "SKRYTE_OZNACENI"))
                (if e-skryte
                  (progn
                    (entmod (subst (cons 1 skryte-clean) (cons 1 skryte) (entget e-skryte)))
                    (entupd e-skryte)
                    (cez-fix (strcat "OZNA\U+010CEN\U+00CD SKRYTE_OZNACENI '" skryte "' -> '" skryte-clean
                                      "' (odstraneny mezery). Nalezeno na: " (cez-entity-loc-str ins)))
                  )
                )
              )
              (cez-warn (strcat "Blok OZNA\U+010CEN\U+00CD: SKRYTE_OZNACENI='" skryte "' obsahuje mezery - "
                                 "VP C kap. 3.7: \"nesmeji se zadavat zadne neviditelne znaky (mezery...)\". "
                                 "Spust CEZ-OPRAVA pro automaticke odstraneni. Nalezeno na: "
                                 (cez-entity-loc-str ins)))
            )
          )
        )
      )
      (cez-log (strcat "Shrnuti (z " (itoa n-total) " bloku OZNA\U+010CEN\U+00CD): SKRYTE_OZNACENI s mezerami="
                        (itoa n-bad)))
    )
  )
)

;; ----------------------------------------------------------------------
;; 7a) Volba tiskoveho stylu (Plot style table) rozvrzeni - jen v CEZ-OPRAVA
;;
;; VP C kap. 3.4.4: tloustka a vysledna barva pri tisku se urcuji podle
;; nastaveneho Plot Style Table (.ctb), ne podle upravy barev v samotnem
;; vykresu. Proto se zde misto prebarvovani entit jen prida moznost
;; prepnout tiskovy styl vsech rozvrzeni (layoutu) vykresu mezi:
;;   - CEZ cernobily tisk dle VP C (cez_dje-ctb.ctb): barvy 10-254 -> cerna,
;;     103 -> maskovaci bila, 254 -> seda, 1-9 -> vlastni barva
;;   - Barevny tisk (acad.ctb): kazda barva se vytiskne jako ona sama
;; ----------------------------------------------------------------------
(setq *cez-ctb-bw* "cez_dje-ctb.ctb")
(setq *cez-ctb-color* "acad.ctb")

;; Nastavi dany soubor plot style table (.ctb) na vsechna rozvrzeni (Layouts)
;; aktualniho vykresu pomoci ActiveX (StyleSheet property Layout objektu)
(defun cez-set-plotstyle-all-layouts (filename / doc layouts lay n-ok n-fail res)
  (setq n-ok 0 n-fail 0)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layouts (vla-get-Layouts doc))
  (vlax-for lay layouts
    (setq res (vl-catch-all-apply 'vla-put-StyleSheet (list lay filename)))
    (if (vl-catch-all-error-p res)
      (progn
        (setq n-fail (1+ n-fail))
        (cez-warn (strcat "Rozvrzeni '" (vla-get-Name lay) "': nepodarilo se nastavit plot style '"
                           filename "' (" (vl-catch-all-error-message res) ")."))
      )
      (setq n-ok (1+ n-ok))
    )
  )
  (cez-log (strcat "  Plot style '" filename "' nastaven na " (itoa n-ok) " rozvrzenich"
                    (if (> n-fail 0) (strcat ", chyba u " (itoa n-fail) ".") ".")))
)

;; Interaktivni dotaz (jen v rezimu CEZ-OPRAVA) - cernobily tisk dle VP C, barevny tisk, nebo preskocit
(defun cez-ask-plot-style ( / ans pstylemode)
  (setq pstylemode (getvar "PSTYLEMODE"))
  (cez-log "\n=== 7a) VOLBA TISKOVEHO STYLU (PLOT STYLE) ROZVRZENI ===")
  (if (/= pstylemode 1)
    (cez-log (strcat "  [INFO]   PSTYLEMODE=" (itoa pstylemode) " - vykres momentalne nepouziva barevne "
                      "zavisly plot style (.ctb). Prirazeni CEZ CTB nemusi mit ocekavany efekt, dokud "
                      "vykres nebude prevedeny do rezimu Color Dependent Plot Style."))
  )
  (initget "Cernobile Barevne Preskocit")
  (setq ans (getkword (strcat "\nZmenit barvy vykresleni tisku vsech rozvrzeni na cernobile dle VP C ("
                               *cez-ctb-bw* ") nebo na barevne (" *cez-ctb-color*
                               ")? [Cernobile/Barevne/Preskocit] <Preskocit>: ")))
  (cond
    ((= ans "Cernobile")
      (cez-set-plotstyle-all-layouts *cez-ctb-bw*)
      (cez-fix (strcat "Tiskovy styl vsech rozvrzeni nastaven na '" *cez-ctb-bw* "' (cernobily tisk dle "
                        "VP C kap. 3.4.4: barvy 10-254 se vytisknou cerne, 1-9 si zachovaji vlastni "
                        "barvu, 103=maskovaci bila, 254=seda). Over, ze mas tento soubor nahrany ve "
                        "slozce Plot Styles AutoCADu (viz Navod pro pouziti sablony a nacteni "
                        "pomocnych souboru)."))
    )
    ((= ans "Barevne")
      (cez-set-plotstyle-all-layouts *cez-ctb-color*)
      (cez-fix (strcat "Tiskovy styl vsech rozvrzeni nastaven na '" *cez-ctb-color*
                        "' (barevny tisk - kazda barva se vytiskne jako ona sama, bez prevodu na "
                        "cernou dle VP C)."))
    )
    (t (cez-log "  Preskoceno - tiskovy styl rozvrzeni nezmenen."))
  )
)

;; ----------------------------------------------------------------------
;; 7b) Prevod zakladnich indexovych barev (1-9) na podobny odstin v rozsahu
;;     10-254 - jen v CEZ-OPRAVA, na vyzadani
;;
;; Na rozdil od 7a) (ktera meni jen odkaz na plot style table) tato funkce
;; PRIMO PREPISUJE barvu (DXF 62) na hladinach i na primo obarvenych
;; entitach. Barvy indexu 1-9 se prevedou na odpovidajici index v rozsahu
;; 10-254 se stejnym/podobnym odstinem dle nasledujici tabulky (zadano
;; uzivatelem):
;;   1 (cervena)    -> 10
;;   2 (zluta)      -> 50
;;   3 (zelena)     -> 90
;;   4 (azurova)    -> 130
;;   5 (modra)      -> 170
;;   6 (purpurova)  -> 210
;;   7 (bila/cerna) -> beze zmeny
;;   8 (tm. seda)   -> 252
;;   9 (sv. seda)   -> 253
;; ----------------------------------------------------------------------
(setq *cez-zakladni-barvy-remap* (list (cons 1 10) (cons 2 50) (cons 3 90) (cons 4 130)
                                        (cons 5 170) (cons 6 210) (cons 8 252) (cons 9 253)))
;; barva 7 (bila/cerna) se dle zadani nemeni - neni v tabulce, cez-remap-color-value pro ni vrati nil

(defun cez-remap-color-value (col / pair)
  (setq pair (assoc col *cez-zakladni-barvy-remap*))
  (if pair (cdr pair) nil)
)

;; Prochazi VSECHNY definice bloku (tblnext "BLOCK") a primo prepisuje barvu
;; (DXF 62) entit ULOZENYCH UVNITR KAZDE DEFINICE BLOKU. Toto je nutne navic
;; k ssget "_X" pruchodu - ssget "_X" vrati jen entity primo v modelovem a
;; papirovem prostoru (vc. samotnych INSERT referenci), ale NE entity, ktere
;; jsou soucasti definice bloku (tj. geometrii, kterou blok "obsahuje").
;; Pokud ma takova vnitrni entita barvu napevno nastavenou (ne ByBlock/
;; ByLayer), pak se bez tohoto pruchodu nikdy neprevede, a blok bude po
;; vlozeni do vykresu stale vypadat se stara barvou bez ohledu na to, co se
;; zmeni na hladinach nebo na samotnem INSERTu.
;; Preskakuji se anonymni bloky (*U..., *Model_Space, *Paper_Space...) a
;; externi reference (XREF/XREF overlay).
(defun cez-remap-colors-in-block-defs ( / tbl bname btype bstart e elist pair-c col newcol n-blocks n-entities)
  (setq n-blocks 0 n-entities 0)
  (setq tbl (tblnext "BLOCK" T))
  (while tbl
    (setq bname (cdr (assoc 2 tbl)))
    (setq btype (cdr (assoc 70 tbl)))
    (if (and (/= (substr bname 1 1) "*")
             (not (and btype (/= 0 (logand btype 12)))))  ;; 4=xref, 8=xref overlay
      (progn
        (setq n-blocks (1+ n-blocks))
        (setq bstart (tblobjname "BLOCK" bname))
        (setq e (entnext bstart))
        (while e
          (setq elist (entget e))
          (setq pair-c (assoc 62 elist))
          (if pair-c
            (progn
              (setq col (cdr pair-c))
              (setq newcol (cez-remap-color-value col))
              (if newcol
                (progn
                  (cez-set-dxf e 62 newcol)
                  (setq n-entities (1+ n-entities))
                )
              )
            )
          )
          (setq e (entnext e))
        )
      )
    )
    (setq tbl (tblnext "BLOCK"))
  )
  (cez-log (strcat "  Prohledano " (itoa n-blocks) " definic bloku (vc. vnorenych), primo obarvenych "
                    "entit uvnitr bloku prevedeno: " (itoa n-entities) "."))
)

(defun cez-convert-basic-colors ( / tbl name color newcol n-layers ss i ent elist pair-c col2 newcol2 n-entities etype2)
  (setq n-layers 0 n-entities 0)
  ;; hladiny
  (setq tbl (tblnext "LAYER" T))
  (while tbl
    (setq name (cdr (assoc 2 tbl)) color (cdr (assoc 62 tbl)))
    (if (< color 0) (setq color (- color)))
    (setq newcol (cez-remap-color-value color))
    (if newcol
      (progn
        (cez-layer-set-color-linetype name newcol nil)
        (setq n-layers (1+ n-layers))
        (cez-fix (strcat "Hladina '" name "': barva " (itoa color) " -> " (itoa newcol) "."))
      )
    )
    (setq tbl (tblnext "LAYER"))
  )
  ;; primo obarvene entity
  (setq ss (ssget "_X"))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) elist (entget ent) etype2 (cdr (assoc 0 elist)))
        (if (not (member etype2 (list "ATTDEF" "VIEWPORT")))
          (progn
            (setq pair-c (assoc 62 elist))
            (if pair-c
              (progn
                (setq col2 (cdr pair-c))
                (setq newcol2 (cez-remap-color-value col2))
                (if newcol2
                  (progn
                    (cez-set-dxf ent 62 newcol2)
                    (if (= etype2 "ATTRIB") (entupd ent))
                    (setq n-entities (1+ n-entities))
                  )
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (cez-log (strcat "  Prevedeno: " (itoa n-layers) " hladin, " (itoa n-entities)
                    " primo obarvenych entit v modelu/rozvrzeni (barva 7/bila-cerna se nemenila)."))
  ;; entity ULOZENE UVNITR definic bloku (viz cez-remap-colors-in-block-defs vyse)
  (cez-remap-colors-in-block-defs)
)

;; Interaktivni dotaz (jen v rezimu CEZ-OPRAVA)
(defun cez-ask-color-remap ( / ans)
  (cez-log "\n=== 7b) PREVOD ZAKLADNICH INDEXOVYCH BAREV (1-9) NA PODOBNY ODSTIN 10-254 ===")
  (cez-log (strcat "  Tabulka prevodu: 1(cervena)->10, 2(zluta)->50, 3(zelena)->90, "
                    "4(azurova)->130, 5(modra)->170, 6(purpurova)->210, "
                    "7(bila/cerna)=beze zmeny, 8(tm.seda)->252, 9(sv.seda)->253."))
  (initget "Ano Ne")
  (setq ans (getkword (strcat "\nPrevest hladiny a primo obarvene entity s barvou indexu 1-9 "
                               "na odpovidajici index dle tabulky vyse? [Ano/Ne] <Ne>: ")))
  (if (= ans "Ano")
    (cez-convert-basic-colors)
    (cez-log "  Preskoceno - zakladni indexove barvy 1-9 nezmeneny.")
  )
)

;; ----------------------------------------------------------------------
;; Hlavni vstupni body
;; ----------------------------------------------------------------------
(defun cez-run (fix-p / dwgname logname f)
  (cez-load-data)
  (if (not *cez-layers*)
    (progn (princ "\n[CEZ] Kontrola prerusena - datova tabulka neni nactena.") (princ))
    (progn
      (setq *cez-report* '())
      (setq *cez-pozor-count* 0)
      (cez-log "============================================================")
      (cez-log (strcat "CEZ_ST_0093 - " (if fix-p "KONTROLA A OPRAVA" "KONTROLA") " VYKRESU"))
      (cez-log (strcat "Vykres: " (getvar "DWGNAME")))
      (cez-log (strcat "Datum:  " (menucmd "M=$(edtime,$(getvar,date),DD.MO.YYYY HH:MM)")))
      (cez-log-silent "@@POCET_POZOR@@")
      (cez-log "============================================================")

      (if fix-p (command "_.UNDO" "_BE"))

      (cez-check-layers fix-p)
      (cez-check-linetypes)
      (cez-check-textstyles)
      (cez-check-titleblock fix-p)
      (cez-check-entity-colors fix-p)
      (cez-check-block-def-colors)
      (cez-check-codepage fix-p)
      (cez-check-layer-zero)
      (cez-check-xref-proxy)
      (cez-check-text-rules)
      (cez-check-dimstyle-usage)
      (cez-check-revize)
      (cez-check-oznaceni fix-p)
      (if fix-p (cez-ask-color-remap))
      (if fix-p (cez-ask-plot-style))

      (cez-log "\n============================================================")
      (cez-log (strcat "Kontrola dokoncena. Celkem nalezeno chyb neodpovidajicich metodice: "
                        (itoa *cez-pozor-count*) "."))
      (cez-log "Pro detailni zaznam viz log soubor.")
      (cez-log "============================================================")

      ;; Nahrazeni placeholderu v hlavicce skutecnym poctem [POZOR] radku
      (setq *cez-report*
        (subst
          (strcat "Pocet nalezenych chyb neodpovidajicich metodice: " (itoa *cez-pozor-count*))
          "@@POCET_POZOR@@"
          *cez-report*
        )
      )

      ;; Ulozeni logu vedle vykresu
      (setq dwgname (getvar "DWGPREFIX"))
      (setq logname (strcat dwgname (vl-filename-base (getvar "DWGNAME"))
                             (if fix-p "_CEZ_oprava.log" "_CEZ_kontrola.log")))
      (setq f (open logname "w"))
      (if f
        (progn
          (foreach line (reverse *cez-report*) (write-line line f))
          (close f)
          (princ (strcat "\n[CEZ] Zapsan log: " logname))
        )
        (princ "\n[CEZ] Log se nepodarilo zapsat (zkontroluj prava k zapisu do slozky vykresu).")
      )
      (if fix-p (command "._REGEN"))
      (if fix-p (command "_.UNDO" "_E"))
      (princ)
    )
  )
)

;; ----------------------------------------------------------------------
;; 8) Auto-update z GitHubu (CEZ-VERZE / CEZ-UPDATE)
;;
;; Pouziva ActiveX/COM objekt MSXML2.ServerXMLHTTP.6.0 (soucast Windows,
;; funguje jen na AutoCADu pro Windows - NE na AutoCADu pro Mac, ktery COM
;; automatizaci nepodporuje) k provedeni synchronniho HTTPS GET pozadavku
;; na "raw" verzi souboru primo z GitHub repozitare
;; https://github.com/Chuck3CZ/cez-autocad-validator, bez nutnosti
;; instalovat cokoli navic (git, curl...). Stazeny obsah se zapise na misto
;; aktualne pouzivaneho lokalniho souboru (dle Support File Search Path) a
;; znovu nacte.
;;
;; POZOR: tato cast nebyla odzkousena v realnem AutoCADu (viz POZOR na
;; zacatku souboru). Pouziva se DVOJI pokus, protoze ruzne COM/ActiveX
;; objekty pro HTTP se v BEZNE FIREMNI SITI S PROXY chovaji ruzne:
;;  1. "MSXML2.XMLHTTP" - klientsky objekt zalozeny na WinInet, ktery
;;     AUTOMATICKY DEDI nastaveni proxy z Internet Exploreru/systemu
;;     (Ovladaci panely > Moznosti internetu, nebo firemni GPO). V siti
;;     s proxy (typicke ve firemnim/dodavatelskem prostredi) je to tedy
;;     nejspolehlivejsi volba.
;;  2. "WinHttp.WinHttpRequest.5.1" - pouziva se jen pokud prvni pokus
;;     selze; respektuje systemove WinHTTP proxy nastaveni (nastavuje se
;;     prikazem "netsh winhttp import proxy source=ie" ve Windows), coz
;;     v nekterych firemnich prostredich take funguje.
;; Pokud selzou OBA pokusy (typicky proxy vyzadujici prihlaseni, nebo
;; firewall blokujici primo AutoCAD.exe misto jen prohlizece), pouzij
;; RUCNI aktualizaci popsanou v README.md ("Rucni aktualizace") - stazeni
;; pres prohlizec funguje vzdy, protoze prohlizec je ve firemni siti
;; skoro vzdy povoleny.
;; ----------------------------------------------------------------------

;; Provede synchronni HTTPS GET na danou URL a vrati obsah jako retezec,
;; nebo nil pri jakekoli chybe (spatne pripojeni, HTTP chyba, blokovana
;; proxy apod.) - viz komentar vyse k poradi pokusu.
(defun cez-http-get (url / http res txt errmsg)
  (setq txt nil errmsg nil)

  ;; 1. pokus: MSXML2.XMLHTTP (WinInet, dedi IE/systemovou proxy)
  (setq res
    (vl-catch-all-apply
      (function
        (lambda ()
          (setq http (vlax-create-object "MSXML2.XMLHTTP"))
          (vlax-invoke http 'Open "GET" url :vlax-false)
          (vlax-invoke http 'setRequestHeader "Cache-Control" "no-cache")
          (vlax-invoke http 'Send)
          (if (= (vlax-get-property http 'Status) 200)
            (setq txt (vlax-get-property http 'ResponseText))
          )
          (vlax-release-object http)
        )
      )
    )
  )
  (if (and (not txt) (vl-catch-all-error-p res)) (setq errmsg (vl-catch-all-error-message res)))

  ;; 2. pokus (jen pokud prvni selhal): WinHttp.WinHttpRequest.5.1
  (if (not txt)
    (progn
      (setq res
        (vl-catch-all-apply
          (function
            (lambda ()
              (setq http (vlax-create-object "WinHttp.WinHttpRequest.5.1"))
              (vlax-invoke http 'SetTimeouts 5000 5000 10000 15000)
              (vlax-invoke http 'Open "GET" url :vlax-false)
              (vlax-invoke http 'setRequestHeader "Cache-Control" "no-cache")
              (vlax-invoke http 'Send)
              (if (= (vlax-get-property http 'Status) 200)
                (setq txt (vlax-get-property http 'ResponseText))
              )
              (vlax-release-object http)
            )
          )
        )
      )
      (if (and (not txt) (vl-catch-all-error-p res)) (setq errmsg (vl-catch-all-error-message res)))
    )
  )

  (if (not txt)
    (progn
      (princ (strcat "\n[CEZ] Nepodarilo se stahnout '" url "'."))
      (if errmsg (princ (strcat "\n[CEZ] Detail posledni chyby: " errmsg)))
      (princ "\n[CEZ] Mozne priciny: firemni proxy/firewall povoluje pristup na internet jen")
      (princ "\n[CEZ] prohlizeci (ne primo AutoCADu), proxy vyzaduje prihlaseni, nebo chybi")
      (princ "\n[CEZ] pripojeni k internetu.")
      (princ "\n[CEZ] Reseni: pouzij RUCNI aktualizaci - viz README.md, sekce 'Rucni aktualizace'")
      (princ "\n[CEZ] (stazeni pres prohlizec + rucni prepsani souboru funguje vzdy).")
    )
  )
  txt
)

;; Vytahne hodnotu *cez-validator-version* z textoveho obsahu .lsp souboru
;; (aniz by se soubor musel nacitat/spoustet) - hleda radek se vzorem
;; (setq *cez-validator-version* "X.Y.Z")
(defun cez-extract-version (content / pos1 pos2 marker)
  (setq marker "(setq *cez-validator-version* \"")
  (setq pos1 (vl-string-search marker content))
  (if pos1
    (progn
      (setq pos1 (+ pos1 (strlen marker)))
      (setq pos2 (vl-string-search "\"" content pos1))
      (if pos2 (substr content (1+ pos1) (- pos2 pos1)) nil)
    )
    nil
  )
)

(defun c:CEZ-VERZE ( / base remote-content remote-ver)
  (princ (strcat "\n[CEZ] Mistni verze: " *cez-validator-version*))
  (setq base (strcat "https://raw.githubusercontent.com/" *cez-github-repo* "/"
                      *cez-github-branch* "/CEZ_ST0093_Validator.lsp"))
  (princ "\n[CEZ] Zjistuji nejnovejsi verzi na GitHubu...")
  (setq remote-content (cez-http-get base))
  (if remote-content
    (progn
      (setq remote-ver (cez-extract-version remote-content))
      (if remote-ver
        (if (= remote-ver *cez-validator-version*)
          (princ (strcat "\n[CEZ] Mas nejnovejsi verzi (" remote-ver ")."))
          (princ (strcat "\n[CEZ] K dispozici je nova verze " remote-ver
                          " (mistni: " *cez-validator-version* "). Spust CEZ-UPDATE pro aktualizaci."))
        )
        (princ "\n[CEZ] Verzi na GitHubu se nepodarilo zjistit (neocekavany obsah souboru).")
      )
    )
    (princ "\n[CEZ] Nepodarilo se pripojit ke GitHubu (zkontroluj pripojeni k internetu/firewall/proxy).")
  )
  (princ)
)

(defun c:CEZ-UPDATE ( / base-main base-data content-main content-data
                       local-main local-data f old-ver new-ver)
  (setq base-main (strcat "https://raw.githubusercontent.com/" *cez-github-repo* "/"
                           *cez-github-branch* "/CEZ_ST0093_Validator.lsp"))
  (setq base-data (strcat "https://raw.githubusercontent.com/" *cez-github-repo* "/"
                           *cez-github-branch* "/CEZ_LAYERS_DATA.lsp"))
  ;; Mistni cesty - tam, odkud je soubor prave nacteny (Support File Search Path)
  (setq local-main (findfile "CEZ_ST0093_Validator.lsp"))
  (setq local-data (findfile "CEZ_LAYERS_DATA.lsp"))
  (if (not local-main)
    (princ "\n[CEZ] CHYBA: CEZ_ST0093_Validator.lsp nenalezen na Support File Search Path - aktualizace preskocena.")
    (progn
      (setq old-ver *cez-validator-version*)
      (princ "\n[CEZ] Stahuji CEZ_ST0093_Validator.lsp z GitHubu...")
      (setq content-main (cez-http-get base-main))
      (princ "\n[CEZ] Stahuji CEZ_LAYERS_DATA.lsp z GitHubu...")
      (setq content-data (cez-http-get base-data))
      (cond
        ((not content-main)
          (princ "\n[CEZ] Stazeni CEZ_ST0093_Validator.lsp selhalo - aktualizace preskocena."))
        ((not content-data)
          (princ "\n[CEZ] Stazeni CEZ_LAYERS_DATA.lsp selhalo - aktualizace preskocena."))
        ((not (and (cez-extract-version content-main) (cez-extract-version content-data)))
          (princ "\n[CEZ] Stazeny soubor neobsahuje platnou verzi - aktualizace preskocena."))
        (t
          (setq f (open local-main "w"))
          (write-line content-main f)
          (close f)
          (if local-data
            (progn
              (setq f (open local-data "w"))
              (write-line content-data f)
              (close f)
            )
            (princ "\n[CEZ] POZOR: CEZ_LAYERS_DATA.lsp nebyl nalezen na Support File Search Path - obsah stazen, ale neni jasne kam ulozit; ulozeno vedle CEZ_ST0093_Validator.lsp.")
          )
          (if (not local-data)
            (progn
              (setq local-data (strcat (vl-filename-directory local-main) "\\CEZ_LAYERS_DATA.lsp"))
              (setq f (open local-data "w"))
              (write-line content-data f)
              (close f)
            )
          )
          (princ "\n[CEZ] Soubory aktualizovany, nacitam novou verzi...")
          (load local-main)
          (setq new-ver *cez-validator-version*)
          (princ (strcat "\n[CEZ] Hotovo. Verze " old-ver " -> " new-ver "."))
        )
      )
    )
  )
  (princ)
)

(defun c:CEZ-KONTROLA ( / ) (cez-run nil) (princ))
(defun c:CEZ-OPRAVA ( / ) (cez-run T) (princ))

;; ----------------------------------------------------------------------
;; 9) Automaticke spusteni CEZ-KONTROLA pri KAZDEM otevreni/zalozeni vykresu
;;
;; NENI aktivni samo od sebe - musi se explicitne zapnout, viz README.md,
;; sekce "Automaticke spusteni kontroly pri otevreni vykresu". Duvod: tohle
;; meni chovani AutoCADu (spousti prikaz bez pozadani), coz by nemelo byt
;; prekvapive, pokud si to uzivatel vyslovne nezapnul.
;;
;; Pouziva se bezpecne zretezeni funkce S::STARTUP - standardni AutoLISP
;; mechanismus, ktery AutoCAD zavola automaticky po nacteni acaddoc.lsp
;; PRO KAZDY VYKRES ZNOVU (na rozdil od Startup Suite/acad.lsp, ktere se
;; nactou jen jednou pri spusteni AutoCADu). Proto MUSI byt volani funkce
;; cez-enable-autorun-on-open v acaddoc.lsp, ne (jen) ve Startup Suite -
;; jinak by se S::STARTUP znovu neregistroval pro druhy a dalsi otevreny
;; vykres. Zretezeni pres defun-q-list-ref/defun-q-list-set (standardni
;; dokumentovany AutoLISP mechanismus prave pro tento ucel) zajisti, ze se
;; neprepise/nezrusi jina existujici automatizace ve S::STARTUP (napr.
;; firemni CAD sablona nebo jiny doplnek) - pouze se na konec pripoji
;; volani teto kontroly.
;;
;; POZOR: stejne jako CEZ-UPDATE, ani tato cast nebyla odzkousena v
;; realnem AutoCADu.
;; ----------------------------------------------------------------------

;; Spusti CEZ-KONTROLA a pokud najde problemy, navic zobrazi (alert),
;; aby si toho uzivatel vsiml i bez sledovani prikazove radky.
(defun cez-auto-check-and-notify ( / )
  (c:CEZ-KONTROLA)
  (if (and (boundp '*cez-pozor-count*) (> *cez-pozor-count* 0))
    (alert (strcat "CEZ kontrola vykresu:\n\nNalezeno " (itoa *cez-pozor-count*)
                    " chyb neodpovidajicich metodice CEZ_ST_0093.\n\n"
                    "Detail viz prikazova radka nebo log soubor vedle vykresu."))
  )
  (princ)
)

;; Zapne automaticke spusteni kontroly pri kazdem otevreni vykresu -
;; zavolej tuto funkci z acaddoc.lsp (viz README.md).
(defun cez-enable-autorun-on-open ( / )
  (if (not (member 'S::STARTUP (atoms-family 1)))
    (defun-q S::STARTUP ())
  )
  (defun-q-list-set 'S::STARTUP
    (append (defun-q-list-ref 'S::STARTUP) (list '(cez-auto-check-and-notify)))
  )
  (princ "\n[CEZ] Automaticke spusteni CEZ-KONTROLA pri otevreni vykresu zapnuto (S::STARTUP).")
  (princ)
)

(princ (strcat "\n[CEZ] Nacten validator/opravator CEZ_ST_0093 v" *cez-validator-version*
               " - prikazy: CEZ-KONTROLA, CEZ-OPRAVA, CEZ-VERZE, CEZ-UPDATE"))
(princ)
