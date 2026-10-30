import { appliesDefault, switchUi } from '@/lib/uiMode'

// Loaded by `reactiveadmin_ui_toggle` on a classic page, as its own entry of the client build.
const panel = document.querySelector<HTMLElement>('[data-reactiveadmin-ui]')

if (panel) {
  if (appliesDefault(panel.dataset.reactiveadminUi)) switchUi('new')
  panel.querySelector('[data-reactiveadmin-ui-mode]')?.addEventListener('click', () => switchUi('new'))
}
