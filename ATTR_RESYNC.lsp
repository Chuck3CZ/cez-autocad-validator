;; ============================================================================
;; ATTR-RESYNC.lsp
;;
;; Pomocny nastroj pro predefinovane bloky se zmenenymi atributy.
;;
;; PROBLEM, ktery resi:
;;   Kdyz predefinujes definici bloku (napr. prikazem BLOCK se stejnym
;;   nazvem, nebo BEDIT+Save), existujici vlozeni (INSERT) toho bloku ve
;;   vykresu si driv nebo pozdeji potrebujes zaktualizovat na nove atributy.
;;   Standardni prikaz ATTSYNC to sice udela (hodnoty u atributu se stejnym
;;   tagem zachova, nove atributy prida s vychozi hodnotou, zrusene smaze),
;;   ALE zaroven VZDY prestavi format/POLOHU VSECH atributu podle aktualni
;;   sablony bloku - tim padem zrusi jakekoli rucni rozmisteni atributu na
;;   jednotlivych vlozeni.
;;
;;   Rucne "dopisovat" novy atribut primo do existujiciho INSERTu pres
;;   entmake/entdel na urovni AutoLISPu neni spolehlive (retezec
;;   INSERT->ATTRIB...->SEQEND je interni strukturu vykresu, kterou takhle
;;   dodatecne rozsirovat neni bezpecne) - proto se pouziva tato kombinace:
;;
;;   1) Pred synchronizaci se pro KAZDE vlozeni bloku ulozi kompletni stav
;;      vsech jeho aktualnich atributu (tag, hodnota, poloha, vyska,
;;      rotace, styl, vrstva, zarovnani).
;;   2) Spusti se nativni ATTSYNC (bezpecne prestavi atributovy retezec
;;      podle aktualni sablony bloku).
;;   3) U atributu, ktere existovaly uz PRED synchronizaci, se bezpecnym
;;      entmod vrati puvodni poloha/format (to je presne to, co samotny
;;      ATTSYNC neumi).
;;   4) Pokud byl novy atribut oznacen (na dotaz pri behu) jako NAHRADA za
;;      stary/zruseny atribut, prevezme jeho hodnotu (text) ze stareho
;;      atributu.
;;   5) Atributy, ktere v nove sablone uz nejsou a nebyly pouzity jako
;;      zdroj prejmenovani, ATTSYNC sam smaze.
;;
;; POUZITI:
;;   0. DULEZITE (predevsim pri predefinovani pres Block Editor - BEDIT):
;;      PRED predefinovanim bloku spust ATTR-SNAPSHOT. AutoCAD totiz casto
;;      pri ulozeni Block Editoru existujici vlozeni sam tise
;;      pre-synchronizuje - stary atribut (tag+hodnota+poloha) je pak uz
;;      nenavratne pryc jeste pred tim, nez vubec stihnes spustit
;;      ATTR-RESYNC. ATTR-SNAPSHOT zalohuje aktualni stav VSECH vlozeni
;;      daneho bloku do pameti relace, aby to nevadilo.
;;   1. Predefinuj blok (BLOCK/BEDIT) tak, jak potrebujes.
;;   2. Spust prikaz ATTR-RESYNC. Staci stisknout Enter bez kliknuti na
;;      geometrii - automaticky se pouzije stejny blok jako u posledniho
;;      ATTR-SNAPSHOT. (Klikem na jine vlozeni, nebo rucnim zadanim nazvu,
;;      lze i tak vybrat jiny blok.)
;;   4. Pro kazdy novy atribut v sablone, ktery jeste zadne vlozeni nema,
;;      se skript zepta, jestli je to nahrada za nejaky stary (zruseny)
;;      atribut, ze ktereho se ma prevzit text I POLOHU/FORMAT. Odpovedet
;;      lze CISLEM z nabidky (napr. "1") nebo presnym TAGem - cislo je
;;      spolehlivejsi, protoze u presneho TAGu se pri jakemkoli preklepu
;;      (napr. zkraceny nazev) cela nabidka pro dany atribut tise preskoci.
;;      Pokud predtim probehl ATTR-SNAPSHOT, pouzije se zalohovany (predchozi)
;;      stav - jinak aktualni stav vlozeni v okamziku spusteni ATTR-RESYNC.
;;   5. Skript provede ATTSYNC + opravu poloh/hodnot pro VSECHNA vlozeni
;;      daneho bloku ve vykresu, vse v jedne UNDO skupine (jeden UNDO vse
;;      vrati zpet).
;;
;; POZOR: Pred pouzitim na ostrem vykresu doporucujeme otestovat na kopii.
;; Presna posloupnost promptu prikazu ATTSYNC se muze mezi verzemi AutoCADu
;; mirne lisit - pokud by prikaz "_ATTSYNC" "_Name" bname "" v tvoji verzi
;; neprobehl podle ocekavani (napr. extra potvrzovaci dotaz navic), zkus
;; nejdriv rucne spustit ATTSYNC na prikazovem radku, over si presnou
;; posloupnost promptu, a pripadne uprav radek s (command "_ATTSYNC" ...).
;; ============================================================================

;; Vrati seznam tagu vsech ATTDEF v aktualni definici bloku bname.
(defun ar-attdef-list (bname / bstart e elist tags)
  (setq tags '())
  (setq bstart (tblobjname "BLOCK" bname))
  (setq e (entnext bstart))
  (while e
    (setq elist (entget e))
    (if (= (cdr (assoc 0 elist)) "ATTDEF")
      (setq tags (cons (cdr (assoc 2 elist)) tags))
    )
    (setq e (entnext e))
  )
  (reverse tags)
)

;; Vrati alist (tag . elist) vsech ATTRIB entit patricich k vlozeni ins,
;; tak jak vypadaly PRED synchronizaci.
(defun ar-save-instance-attrs (ins / e elist tag lst)
  (setq lst '())
  (setq e (entnext ins))
  (while (and e (= (cdr (assoc 0 (entget e))) "ATTRIB"))
    (setq elist (entget e))
    (setq tag (cdr (assoc 2 elist)))
    (setq lst (cons (cons tag elist) lst))
    (setq e (entnext e))
  )
  lst
)

;; Vrati elist s prepsanym/pridanym DXF kodem code na hodnotu newpair
;; (cons code . value). Pokud je newpair nil, elist vrati beze zmeny.
(defun ar-set-dxf (elist code newpair)
  (cond
    ((null newpair) elist)
    ((assoc code elist) (subst newpair (assoc code elist) elist))
    (t (append elist (list newpair)))
  )
)

(defun ar-join (lst sep / s x)
  (setq s (car lst))
  (foreach x (cdr lst) (setq s (strcat s sep x)))
  s
)

;; Interaktivne se zepta na mapovani "novy tag" -> "stary tag", ze ktereho
;; se ma prevzit text. missing-new = tagy v sablone bez existujici hodnoty,
;; missing-old = stare tagy, ktere v nove sablone uz nejsou.
;; Vraci alist (novy-tag . stary-tag).
;; Sestavi cislovanou nabidku "1=tag1, 2=tag2, ..." z lst.
(defun ar-numbered-list (lst / s n x)
  (setq s "" n 0)
  (foreach x lst
    (setq n (1+ n))
    (setq s (strcat s (if (= s "") "" ", ") (itoa n) "=" x))
  )
  s
)

(defun ar-ask-rename-map (missing-new missing-old / map avail newtag choice realtag idx)
  (princ "\n[ATTR-RESYNC] POZOR: na nasledujici otazky se odpovida psanim na klavesnici")
  (princ " (cislo nebo tag + Enter), NE klikanim mysi do vykresu.")
  (setq map '() avail missing-old)
  (foreach newtag missing-new
    (if avail
      (progn
        ;; getstring s T = povoli mezery ve vstupu (jinak by AutoCAD bral
        ;; mezera jako Enter a vstup by se tise usekl uz na ni)
        (setq choice
          (getstring T
            (strcat "\nNovy atribut '" newtag "' - je to nahrada za stary atribut? "
                    "NAPIS na klavesnici cislo nebo presny TAG stareho atributu "
                    "[" (ar-numbered-list avail) "] - NEKLIKEJ mysi do vykresu "
                    "(Enter = preskocit, pouzije se vychozi hodnota ze sablony): ")
          )
        )
        ;; oriznout pripadne nechtene mezery na zacatku/konci (napr. z
        ;; kopirovani/vkladani textu)
        (setq choice (vl-string-trim " \t" choice))
        (if (/= choice "")
          (progn
            ;; nejdriv zkusit cislo z nabidky (odolne proti preklepu v dlouhem
            ;; tagu), teprve pak presny TAG bez ohledu na velikost pismen
            (setq idx (atoi choice))
            (setq realtag
              (if (and (> idx 0) (<= idx (length avail)))
                (nth (1- idx) avail)
                (car (vl-remove-if-not '(lambda (x) (= (strcase x) (strcase choice))) avail))
              )
            )
            (if realtag
              (progn
                (setq map (cons (cons newtag realtag) map))
                (setq avail (vl-remove realtag avail))
                (princ (strcat "\n  [ATTR-RESYNC] OK: '" newtag "' <- '" realtag "' (prevezme hodnotu i polohu)."))
              )
              (princ (strcat "\n  [ATTR-RESYNC] '" choice "' nenalezen mezi nabidkou - preskoceno pro '" newtag "'."))
            )
          )
        )
      )
    )
  )
  map
)

(setq *ar-snapshot* nil)          ; alist: (bname . (list (cons handle saved-attrs)))
(setq *ar-snapshot-old-tags* nil) ; alist: (bname . list-of-tagu)
(setq *ar-last-block* nil)        ; nazev bloku posledniho ATTR-SNAPSHOT - ATTR-RESYNC
                                   ; ho pouzije automaticky, kdyz jen stisknes Enter bez kliknuti

;; ATTR-SNAPSHOT: spust PRED predefinovanim bloku (BLOCK/BEDIT+Save).
;; Duvod: kdyz blok predefinujes pres Block Editor, AutoCAD si existujici
;; vlozeni casto tise sam pre-synchronizuje uz pri ulozeni editoru - stary
;; atribut (tag+hodnota+poloha) je v tu chvili nenavratne pryc a
;; ATTR-RESYNC uz by pak nemel co nabidnout jako zdroj pro prejmenovani.
;; ATTR-SNAPSHOT proto zaloha stav VSECH vlozeni daneho bloku jeste driv,
;; nez k predefinici vubec dojde - ATTR-RESYNC pak (pokud zalohu najde)
;; pouzije tuto zalohu misto aktualniho (uz pripadne prepsaneho) stavu.
(defun c:ATTR-SNAPSHOT ( / sel elist0 bname ss i ins saved old-tags saved-attrs p)
  (setq sel (entsel "\nPRED predefinovanim bloku: vyber existujici vlozeni (INSERT), jehoz atributy chces zazalohovat - klikni na geometrii bloku: "))
  (setq bname nil)
  (if sel
    (progn
      (setq elist0 (entget (car sel)))
      (if (= (cdr (assoc 0 elist0)) "INSERT")
        (setq bname (cdr (assoc 2 elist0)))
        (princ "\n[ATTR-SNAPSHOT] Vybrana entita neni INSERT (blok) - zadej nazev bloku rucne.")
      )
    )
  )
  (if (not bname) (setq bname (getstring T "\nNazev bloku k zazalohovani: ")))
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 bname))))
  (if (not ss)
    (princ (strcat "\n[ATTR-SNAPSHOT] Ve vykresu nejsou zadna vlozeni bloku '" bname "'."))
    (progn
      (setq saved '() old-tags '())
      (setq i 0)
      (while (< i (sslength ss))
        (setq ins (ssname ss i))
        (setq saved-attrs (ar-save-instance-attrs ins))
        (setq saved (cons (cons (cdr (assoc 5 (entget ins))) saved-attrs) saved))
        (foreach p saved-attrs
          (if (not (member (car p) old-tags)) (setq old-tags (cons (car p) old-tags)))
        )
        (setq i (1+ i))
      )
      (setq *ar-snapshot*
        (cons (cons bname saved) (vl-remove-if '(lambda (x) (= (car x) bname)) *ar-snapshot*)))
      (setq *ar-snapshot-old-tags*
        (cons (cons bname old-tags) (vl-remove-if '(lambda (x) (= (car x) bname)) *ar-snapshot-old-tags*)))
      (setq *ar-last-block* bname)
      (princ (strcat "\n[ATTR-SNAPSHOT] Zazalohovano " (itoa (sslength ss)) " vlozeni bloku '" bname
                      "' (" (itoa (length old-tags)) " ruznych tagu)."
                      " Ted muzes blok bezpecne predefinovat (BLOCK/BEDIT+Save) a pak spustit ATTR-RESYNC"
                      " (staci Enter bez klikani - pouzije se tento blok automaticky) -"
                      " pouzije tuto zalohu, i kdyz mezitim AutoCAD atributy na vlozenich sam pre-synchronizoval."))
    )
  )
  (princ)
)

(defun c:ATTR-RESYNC ( / sel elist0 bname ss i ins new-tags old-tags missing-new missing-old
                       rename-map saved saved-attrs p rec h e elist tag oldpair map-pair srcpair code snap snap-tags)
  (setq sel (entsel
    (strcat "\nVyber existujici vlozeni (INSERT) predefinovaneho bloku - klikni na geometrii bloku, ne na text atributu"
            (if *ar-last-block* (strcat " (Enter = pouzit posledne zazalohovany blok '" *ar-last-block* "')") "")
            ": ")
  ))
  (setq bname nil)
  (if sel
    (progn
      (setq elist0 (entget (car sel)))
      (if (= (cdr (assoc 0 elist0)) "INSERT")
        (setq bname (cdr (assoc 2 elist0)))
        (princ "\n[ATTR-RESYNC] Vybrana entita neni INSERT (blok) - zadej nazev bloku rucne.")
      )
    )
  )
  (if (and (not bname) *ar-last-block*)
    (progn
      (setq bname *ar-last-block*)
      (princ (strcat "\n[ATTR-RESYNC] Nic nevybrano - pouzivam posledne zazalohovany blok '" bname "'."))
    )
  )
  (if (not bname) (setq bname (getstring T "\nNazev bloku k synchronizaci: ")))

  (cond
    ((not (tblsearch "BLOCK" bname))
      (princ (strcat "\n[ATTR-RESYNC] Blok '" bname "' neexistuje v tabulce bloku - zkontroluj nazev."))
    )
    (t
      (setq new-tags (ar-attdef-list bname))
      (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 bname))))
      (if (not ss)
        (princ (strcat "\n[ATTR-RESYNC] Ve vykresu nejsou zadna vlozeni bloku '" bname "'."))
        (progn
          ;; Pokud existuje drivejsi ATTR-SNAPSHOT tohoto bloku, pouzit jeho ulozeny
          ;; stav (spolehlive i kdyz AutoCAD mezitim atributy na vlozenich uz sam
          ;; pre-synchronizoval pri ulozeni Block Editoru). Jinak (zadny snapshot)
          ;; zalohovat aktualni stav VSECH vlozeni ted - funguje jen pokud predefinice
          ;; bloku sama o sobe existujici vlozeni jeste neprepsala.
          (setq snap (assoc bname *ar-snapshot*))
          (setq snap-tags (assoc bname *ar-snapshot-old-tags*))
          (if snap
            (progn
              (setq saved (cdr snap) old-tags (cdr snap-tags))
              (princ (strcat "\n[ATTR-RESYNC] Pouzivam drivejsi ATTR-SNAPSHOT bloku '" bname "'."))
            )
            (progn
              (setq saved '() old-tags '())
              (setq i 0)
              (while (< i (sslength ss))
                (setq ins (ssname ss i))
                (setq saved-attrs (ar-save-instance-attrs ins))
                (setq saved (cons (cons (cdr (assoc 5 (entget ins))) saved-attrs) saved))
                (foreach p saved-attrs
                  (if (not (member (car p) old-tags)) (setq old-tags (cons (car p) old-tags)))
                )
                (setq i (1+ i))
              )
            )
          )

          (setq missing-new (vl-remove-if '(lambda (x) (member x old-tags)) new-tags))
          (setq missing-old (vl-remove-if '(lambda (x) (member x new-tags)) old-tags))

          (princ (strcat "\n[ATTR-RESYNC] Blok '" bname "': " (itoa (sslength ss)) " vlozeni, "
                          (itoa (length new-tags)) " atributu v aktualni sablone."))
          (if missing-new
            (princ (strcat "\n  Nove atributy bez existujici hodnoty: " (ar-join missing-new ", ")))
          )
          (if missing-old
            (princ (strcat "\n  Stare atributy mimo novou sablonu (budou smazany, pokud nebudou pouzity jako zdroj prejmenovani): "
                            (ar-join missing-old ", ")))
          )

          (setq rename-map (if (and missing-new missing-old) (ar-ask-rename-map missing-new missing-old) '()))
          (if rename-map
            (progn
              (princ "\n[ATTR-RESYNC] Namapovano (novy tag -> stary tag, hodnota+poloha se prevezme):")
              (foreach map-pair rename-map
                (princ (strcat "\n  '" (car map-pair) "' <- '" (cdr map-pair) "'"))
              )
            )
            (princ "\n[ATTR-RESYNC] Zadne mapovani novy<->stary atribut (nebylo co nabidnout, nebo jsi vsechno preskocil Enterem).")
          )

          (command "_.UNDO" "_BE")
          (command "_ATTSYNC" "_Name" bname "")

          ;; Po synchronizaci: vratit puvodni polohu/format u atributu, ktere
          ;; existovaly uz drive, a doplnit hodnotu u prejmenovanych atributu.
          (foreach rec saved
            (setq h (car rec) saved-attrs (cdr rec))
            (setq ins (handent h))
            (if ins
              (progn
                (setq e (entnext ins))
                (while (and e (= (cdr (assoc 0 (entget e))) "ATTRIB"))
                  (setq elist (entget e) tag (cdr (assoc 2 elist)))
                  (setq oldpair (assoc tag saved-attrs))
                  (cond
                    (oldpair
                      (setq oldpair (cdr oldpair))
                      ;; tag existoval uz drive - vratit puvodni polohu/format
                      ;; (hodnotu uz spravne zachoval samotny ATTSYNC)
                      (foreach code '(8 7 10 11 40 41 50 51 62 72 74)
                        (setq elist (ar-set-dxf elist code (assoc code oldpair)))
                      )
                      (entmod elist)
                      (entupd e)
                    )
                    (t
                      ;; novy tag - pokud je namapovan na stary (prejmenovany atribut),
                      ;; prevzit z nej text I POLOHU/FORMAT (stejne jako u nezmenenych
                      ;; tagu vyse) - ATTSYNC u prejmenovaneho tagu zadnou puvodni
                      ;; hodnotu ani polohu neresi, je to zcela novy atribut
                      (setq map-pair (assoc tag rename-map))
                      (if (not map-pair)
                        (princ (strcat "\n[ATTR-RESYNC] DEBUG: atribut '" tag
                                        "' neni v mapovani - ponechana vychozi hodnota ze sablony (\""
                                        (cdr (assoc 1 elist)) "\")."))
                      )
                      (if map-pair
                        (progn
                          (setq srcpair (assoc (cdr map-pair) saved-attrs))
                          (if (not srcpair)
                            (princ (strcat "\n[ATTR-RESYNC] DEBUG: atribut '" tag
                                            "' je namapovan na '" (cdr map-pair)
                                            "', ale ten v zaloze nenalezen (?) - ponechana vychozi hodnota."))
                          )
                          (if srcpair
                            (progn
                              (setq srcpair (cdr srcpair))
                              (foreach code '(1 8 7 10 11 40 41 50 51 62 72 74)
                                (setq elist (ar-set-dxf elist code (assoc code srcpair)))
                              )
                              (entmod elist)
                              (entupd e)
                              (princ (strcat "\n[ATTR-RESYNC] DEBUG: atribut '" tag
                                              "' <- '" (cdr map-pair) "', hodnota nyni: \""
                                              (cdr (assoc 1 srcpair)) "\""))
                            )
                          )
                        )
                      )
                    )
                  )
                  (setq e (entnext e))
                )
              )
            )
          )
          (command "_.UNDO" "_E")
          (princ (strcat "\n[ATTR-RESYNC] Hotovo - zaktualizovano " (itoa (sslength ss)) " vlozeni bloku '" bname "'."))
        )
      )
    )
  )
  (princ)
)


;; ============================================================================
;; ATTR-COPY / ATTR-PASTE
;;
;; Jednoduchy doplnkovy nastroj pro rucni prenos OBSAHU I POLOHY/FORMATU
;; mezi atributy/textem - typicky kdyz rusis stary atribut a chces jeho
;; hodnotu i presne umisteni prenest do nove pridaneho, mimo cely
;; ATTR-RESYNC postup (napr. jen jeden konkretni atribut, nebo TEXT/MTEXT
;; entita mimo blok).
;;
;; Nejde o systemovou (OS) schranku Windows - data se drzi jen v pameti
;; aktualni relace AutoCADu (promenna *ar-clipboard*). To je zamerne:
;; funguje spolehlive bez ohledu na verzi/nastaveni OS schranky a bez zavislosti
;; na ActiveX/COM.
;;
;; POUZITI:
;;   1. Pred smazanim stareho atributu: spust ATTR-COPY a klikni primo na
;;      text puvodniho atributu (ne na geometrii bloku).
;;   2. Smaz stary atribut / pridej novy jak potrebujes (napr. predefinuj
;;      blok s novym atributem na jinem miste/vychozim formatu).
;;   3. Spust ATTR-PASTE a klikni na novy (nebo jakykoli jiny) atribut/text -
;;      prepise se obsahem, polohou, vyskou, rotaci, stylem, vrstvou i
;;      barvou ze schranky (presne umisteni puvodniho atributu).
;;
;; Funguje na ATTRIB, ATTDEF, TEXT i MTEXT entitach.
;; ============================================================================

;; DXF kody, ktere ATTR-COPY/ATTR-PASTE prenasi: 1=text, 7=styl, 8=vrstva,
;; 10/11=poloha, 40=vyska, 41=sirkovy faktor, 50=rotace, 51=sklon,
;; 62=barva, 72/73/74=zarovnani.
(setq *ar-copy-codes* (list 1 7 8 10 11 40 41 50 51 62 72 73 74))
(setq *ar-clipboard* nil)

(defun c:ATTR-COPY ( / sel elist etype code pair)
  (setq sel (entsel "\nVyber atribut/text, jehoz obsah a polohu chces zkopirovat: "))
  (if (not sel)
    (princ "\n[ATTR-COPY] Nic nevybrano.")
    (progn
      (setq elist (entget (car sel)))
      (setq etype (cdr (assoc 0 elist)))
      (if (member etype (list "ATTRIB" "ATTDEF" "TEXT" "MTEXT"))
        (progn
          (setq *ar-clipboard* '())
          (foreach code *ar-copy-codes*
            (setq pair (assoc code elist))
            (if pair (setq *ar-clipboard* (cons pair *ar-clipboard*)))
          )
          (princ (strcat "\n[ATTR-COPY] Zkopirovano (" etype ", vc. polohy/formatu): \""
                          (cdr (assoc 1 elist)) "\""))
        )
        (princ (strcat "\n[ATTR-COPY] Vybrana entita (" etype ") neni ATTRIB/ATTDEF/TEXT/MTEXT - nelze zkopirovat."))
      )
    )
  )
  (princ)
)

(defun c:ATTR-PASTE ( / sel elist etype code pair)
  (cond
    ((not *ar-clipboard*)
      (princ "\n[ATTR-PASTE] Schranka je prazdna - nejdriv pouzij ATTR-COPY.")
    )
    (t
      (setq sel (entsel "\nVyber atribut/text, do ktereho chces vlozit zkopirovany obsah a polohu: "))
      (if (not sel)
        (princ "\n[ATTR-PASTE] Nic nevybrano.")
        (progn
          (setq elist (entget (car sel)))
          (setq etype (cdr (assoc 0 elist)))
          (cond
            ((member etype (list "ATTRIB" "ATTDEF" "TEXT" "MTEXT"))
              (if (= etype "MTEXT")
                ;; odstranit stare pokracovaci retezce (kod 3), aby po vlozeni
                ;; kratsi hodnoty nezustaly za ni viset zbytky puvodniho textu
                (setq elist (vl-remove-if '(lambda (p) (= (car p) 3)) elist))
              )
              (foreach code *ar-copy-codes*
                (setq pair (assoc code *ar-clipboard*))
                (if pair (setq elist (ar-set-dxf elist code pair)))
              )
              (entmod elist)
              (entupd (car sel))
              (princ (strcat "\n[ATTR-PASTE] Vlozeno (" etype ", vc. polohy/formatu): \""
                              (cdr (assoc 1 *ar-clipboard*)) "\""))
            )
            (t
              (princ (strcat "\n[ATTR-PASTE] Vybrana entita (" etype ") neni ATTRIB/ATTDEF/TEXT/MTEXT - nelze vlozit."))
            )
          )
        )
      )
    )
  )
  (princ)
)

(princ "\n[ATTR-RESYNC] Nacten nastroj pro synchronizaci atributu predefinovanych bloku (v1.5) - prikazy: ATTR-SNAPSHOT, ATTR-RESYNC, ATTR-COPY, ATTR-PASTE")
(princ)
