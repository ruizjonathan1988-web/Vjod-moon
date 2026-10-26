/**
 * VJOD - TV Navigation Helper (tv_navigation.js)
 * S'active uniquement sur les navigateurs de Smart TV (Tizen, webOS, etc.)
 * pour permettre une navigation fluide par télécommande (D-Pad).
 */
(function () {
  'use strict';

  // 1. Détection automatique des environnements TV
  function isTvBrowser() {
    const ua = navigator.userAgent.toLowerCase();
    return (
      ua.includes('smart-tv') ||
      ua.includes('smarttv') ||
      ua.includes('googletv') ||
      ua.includes('netcast') || // LG webOS
      ua.includes('tizen') ||    // Samsung Tizen
      ua.includes('hbbtv') ||
      ua.includes('appletv')
    );
  }

  // SÉCURITÉ ABSOLUE : Si ce n'est pas une TV, le script s'arrête net ici.
  // Zéro impact, zéro modification sur PC, tablettes et smartphones.
  if (!isTvBrowser()) {
    return;
  }

  // 2. Injection automatique des styles de focus pour grand écran
  const style = document.createElement('style');
  style.textContent = `
    body.tv-mode *:focus,
    body.tv-mode .focusable-card:focus,
    body.tv-mode button:focus,
    body.tv-mode a:focus {
      outline: 4px solid #3b82f6 !important;
      outline-offset: 4px !important;
      transform: scale(1.04);
      transition: transform 0.15s ease-in-out, outline 0.15s ease-in-out;
      z-index: 9999 !important;
    }
  `;
  document.head.appendChild(style);
  document.body.classList.add('tv-mode');

  // 3. Gestionnaire des touches de la télécommande (D-Pad)
  window.addEventListener('keydown', function (e) {
    const supportedKeys = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter'];
    if (!supportedKeys.includes(e.key)) return;

    // Empêche le comportement natif erratique (scroll de page non désiré) sur la TV
    e.preventDefault();

    // Récupère les éléments interactifs de la page
    const focusables = Array.from(
      document.querySelectorAll('button, a, input, select, [tabindex="0"], [role="button"], .focusable-card')
    );
    
    if (focusables.length === 0) return;

    const current = document.activeElement;
    let index = focusables.indexOf(current);

    // Si aucun élément n'a le focus, on sélectionne le premier par défaut
    if (index === -1) {
      focusables[0].focus();
      return;
    }

    // Estimation du nombre de colonnes pour les grilles de médias
    const columnsEstimate = 4;

    switch (e.key) {
      case 'ArrowRight':
        index = Math.min(focusables.length - 1, index + 1);
        break;
      case 'ArrowLeft':
        index = Math.max(0, index - 1);
        break;
      case 'ArrowDown':
        index = Math.min(focusables.length - 1, index + columnsEstimate);
        break;
      case 'ArrowUp':
        index = Math.max(0, index - columnsEstimate);
        break;
      case 'Enter':
        if (current && typeof current.click === 'function') {
          current.click();
        }
        return;
    }

    const target = focusables[index];
    if (target) {
      target.focus();
      target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
    }
  }, true);

  console.info('VJOD TV Navigation initialized successfully.');
})();
