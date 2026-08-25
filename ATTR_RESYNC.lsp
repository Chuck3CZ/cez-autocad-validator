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
;;   1. Nejdriv predefinuj blok (BLOCK/BEDIT) tak, jak potrebujes.
;;   2. Spust prikaz ATTR-RESYNC.
;;   3. Klikni na existujici vlozeni predefinovaneho bloku (na geometrii,
;;      ne na text atributu), nebo zadej nazev bloku rucne.
;;   4. Pro kazdy novy atribut v sablone, ktery jeste zadne vlozeni nema,
;;      se skript zepta, jestli je to nahrada za nejaky stary (zruseny)
;;      atribut, ze ktereho se ma prevzit text.
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
(defun ar-ask-rename-map (missing-new missing-old / map avail newtag choice realtag)
  (setq map '() avail missing-old)
  (foreach newtag missing-new
    (if avail
      (progn
        (setq choice
          (getstring
            (strcat "\nNovy atribut '" newtag "' - je to nahrada za stary atribut? "
                    "Zadej TAG stareho atributu [" (ar-join avail "/") "] "
                    "(Enter = preskocit, pouzije se vychozi hodnota ze sablony): ")
          )
        )
        (setq choice (strcase choice))
        (if (/= choice "")
          (progn
            (setq realtag (car (vl-remove-if-not '(lambda (x) (= (strcase x) choice)) avail)))
            (if realtag
              (progn
                (setq map (cons (cons newtag realtag) map))
                (setq avail (vl-remove realtag avail))
              )
              (princ (strcat "\n  [ATTR-RESYNC] Tag '" choice "' nenalezen mezi nabidkou - preskoceno."))
            )
          )
        )
      )
    )
  )
  map
)

(defun c:ATTR-RESYNC ( / sel elist0 bname ss i ins new-tags old-tags missing-new missing-old
                       rename-map saved saved-attrs p rec h e elist tag oldpair map-pair srcpair code)
  (setq sel (entsel "\nVyber existujici vlozeni (INSERT) predefinovaneho bloku - klikni na geometrii bloku, ne na text atributu: "))
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
          ;; Ulozit stav VSECH vlozeni PRED synchronizaci.
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
                      ;; novy tag - pokud je namapovan na stary, prevzit text
                      (setq map-pair (assoc tag rename-map))
                      (if map-pair
                        (progn
                          (setq srcpair (assoc (cdr map-pair) saved-attrs))
                          (if srcpair
                            (progn
                              (setq elist (ar-set-dxf elist 1 (assoc 1 (cdr srcpair))))
                              (entmod elist)
                              (entupd e)
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

(princ "\n[ATTR-RESYNC] Nacten nastroj pro synchronizaci atributu predefinovanych bloku - prikaz: ATTR-RESYNC")
(princ)
