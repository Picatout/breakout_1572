Jeu breakout
============

Introduction
------------
  Le jeu d'arcade [breakout](https://fr.wikipedia.org/wiki/Breakout_(jeu_vid%C3%A9o,_1976)) date de 1976. Il s'agit d'un dérivé du jeu pong.
  L'Objectif est de détruire un mur de briques avec une balle qui rebondie sur une raquette qui est au bas de l'écran. Dans cette version
  du jeu le mur comprend 6 rangés de 12 briques. 
  
  Le joueur dispose de 3 balles. Si une balle manque la raquette est elle perdue. Lorsque la balle frappe une brique elle rebondie mais la brique
  disparaît. 
  
  Le pointage se compte de la façon suivante, La rangée du haut est la rangée 1 et celle du bas 6.
  
  rangée | couleur | points
  -------|---------|--------
  1 | jaune | 9
  2 | jaune | 9
  3 | mauve | 7
  4 | mauve | 5
  5 | bleu | 3
  6 | bleu | 1
  
  Le pointage maximal est donc de 24*9+12*7+12*5+12*3+12=408
  
  
Objectif du projet
------------------
	Mon ojectif avec ce projet était de créer le circuit le plus simple possible pouvant générer un signal composite couleur répondant au standard NTSC.
	Le circuit que j'ai conçu ne comprend que 2 composants actifs, soit un microcontrôleur PIC12F1572 et un oscillateur a cristal de 28.636Mhz. Tous les
	autres composants sont passifs et pour l'essentiel il s'agit de condensateurs et de résistances.
	
	Ce circuit peut générer les 6 couleurs suivantes.
	
couleur      |  C (RA1) |  Y (RA4)
-------------|----------|-------------
noir       |    Z     |  Z
blanc      |    Z     |  1
jauce      |    R     |  1
mauve      |    I     |  1
bleu       |    I     |  Z
vert-foncé |    R     |  Z 
    

légende | description
---------|-----------
**Z** | broche en haute impédance
**R** | signal chroma en phase avec le chroma sync
**I** | signal chroma en inversion de phase avec le chroma sync
**1** | sortie Y au niveau Vdd.
**Y** | signal niveau luminance
**C** | signal chroma 3.579545Mhz
       
    Le signal vidéo n'est pas controlé avec le registre **LATA** mais avec le registre TRISA. Pour couper un signal le bit **TRISA** correspondant à la broche
    est mis à 1. Pour activé le signal il est mis à zéro.  Par exemple pour produire du blanc le bit corresponand à **RA4** dans **TRISA** est mis à **0** tandis
    que le bit correspondant à **RA1** est mis à 1.  Le bit **RA4** dans **LATA** est initialisé à **1** et demeure à ce niveau en permance.
    
	Le PIC12F1572 est disponible en format DIP 8 broches. L'utilisation des broches est la suivante.
	
broche |  signal
-------|--------
RA0  |  sortie audio et lecteur du potentiomètre
RA1  |  sortie chroma  (C)
RA2  |  sortie synchronisation
RA3  |  entrée bouton
RA4  |  sortie luminance (Y)
RA5  |  entrée de l'oscillateur externe.
      
    L'oscillateur externe a été sélectionné à la fréquence de 28.636 Mhz parce que cette fréquence correspond à 8 fois la fréquence du signal chromatique du 
    standard NTSC. Ce qui permet de générer un signal chromatique en utilisant un périphérique PWM.  Le standard NTSC utilise la modulation de phase pour
    déterminer la couleur et puisque le PWM du PIC12F1572 permette d'inverse la phase de sortie simplement en commutant un bit dans le registre PWMxCON
    on peut de ce fait produire 2 couleurs différentes simplement en commutant ce bit. Sans cette possibilitée ce circuit ne pourrait produire que 4 couleurs
    au lieu de 6.
    
     
    
      
