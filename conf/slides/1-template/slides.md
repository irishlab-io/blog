---
theme: seriph
background: https://cover.sli.dev
title: "Le Shift-Left en pratique : Intégrer la sécurité avec les pre-commit hooks"
info: |
  ## OWASP Montréal - Novembre 2025
  Le Shift-Left en pratique : Intégrer la sécurité avec les pre-commit hooks

  Par Simon Harvey
class: text-center
drawings:
  persist: false
transition: slide-left
mdc: true
contextMenu: false
routerMode: hash
---

# OWASP Montréal

## Novembre 2025

<div class="text-lg mt-4 opacity-80">
  Le "Shift-Left" en pratique : Intégrer la sécurité avec les pre-commit hooks
</div>

<div class="abs-br m-6 text-xl">
  <a href="https://github.com/irishlab-io/pyquiz" target="_blank" class="slidev-icon-btn">
    <carbon:logo-github />
  </a>
</div>

<!--
Bienvenue à la conférence OWASP Montréal.
Aujourd'hui on parle de DevSecOps, plus précisément comment on peut encourager les développeurs à s'engager dans un mindset shift-left via l'utilisation de pre-commit hooks.
-->

---
transition: fade-out
layout: two-cols
layoutClass: gap-8
---

# $ whoami

**Simon HARVEY**

Conseiller principal en DevSecOps @ **Desjardins**

<div class="flex justify-center mt-12">
  <img src="https://avatars.githubusercontent.com/u/13018674?v=4" class="w-40 h-40 rounded-full shadow-lg" alt="Simon Harvey" />
</div>

::right::

<div class="mt-12">

<div class="flex justify-center gap-8 mt-8">
  <a href="https://www.linkedin.com/in/simon-harvey-a0305029/" target="_blank" class="slidev-icon-btn">
    <carbon:logo-linkedin /> LinkedIn
  </a>
  <a href="https://github.com/irish1986" target="_blank" class="slidev-icon-btn">
    <carbon:logo-github /> GitHub
  </a>
</div>

<div class="mt-8 text-sm">

<div class="flex items-center gap-3 mb-3">
  <carbon:security class="text-blue-400 text-lg flex-shrink-0" />
  <span>Équipe de <strong>Sécurité Applicative</strong></span>
</div>

<div class="flex items-center gap-3 mb-3">
  <carbon:time class="text-blue-400 text-lg flex-shrink-0" />
  <span>20 ans en aéronautique, défense et finances</span>
</div>

<div class="flex items-center gap-3 mb-3">
  <carbon:earth class="text-blue-400 text-lg flex-shrink-0" />
  <span>Canada, États-Unis, Mexique, Irlande du Nord</span>
</div>

</div>
</div>

---
transition: fade-out
---

# Objectif de la présentation

---
layout: center
class: text-center
---

# Merci ! 🙏

<div class="mt-8 grid grid-cols-3 gap-8">

<div>
  <carbon:logo-github class="text-4xl mb-2" />
  <div class="text-sm">

[irishlab-io/pyquiz](https://github.com/irishlab-io/pyquiz)

  </div>
</div>

<div>
  <carbon:logo-linkedin class="text-4xl mb-2" />
  <div class="text-sm">

[simon-harvey](https://www.linkedin.com/in/simon-harvey-a0305029/)

  </div>
</div>

<div>
  <carbon:globe class="text-4xl mb-2" />
  <div class="text-sm">

[irishlab.io](https://irishlab.io)

  </div>
</div>

</div>

<div class="mt-12 text-2xl">

**Questions ?** 🤔

</div>
