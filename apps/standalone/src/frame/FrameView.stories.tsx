import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import { FrameView } from './FrameView'

// Formtastic markup as ActiveAdmin renders it, covering every control the stylesheet maps.
const kitchenSink = `
<form class="formtastic content_plan" action="/admin/content_plans" method="post" accept-charset="UTF-8">
  <input type="hidden" name="authenticity_token" value="x">
  <fieldset class="inputs"><legend><span>Plan details</span></legend><ol>
    <li class="string input required stringish" id="plan_name_input"><label class="label" for="plan_name">Name<abbr title="required">*</abbr></label><input id="plan_name" name="plan[name]" type="text" value="Weekly digest, 12 weeks"><p class="inline-hints">Shown to the author.</p></li>
    <li class="email input optional stringish" id="plan_email_input"><label class="label" for="plan_email">Contact email</label><input id="plan_email" name="plan[email]" type="email" placeholder="editors@example.com"></li>
    <li class="number input optional numeric stringish" id="plan_weeks_input"><label class="label" for="plan_weeks">Weeks</label><input id="plan_weeks" name="plan[weeks]" type="number" value="12" step="1"></li>
    <li class="select input optional" id="plan_state_input"><label class="label" for="plan_state">State</label><select id="plan_state" name="plan[state]"><option value="">Please select</option><option value="CA" selected>California</option><option value="NY">New York</option></select></li>
    <li class="date_picker input optional" id="plan_starts_input"><label class="label" for="plan_starts">Starts on</label><input id="plan_starts" class="datepicker" data-reactiveadmin-widget="date" type="text" name="plan[starts_on]" value="2026-10-20" maxlength="10"></li>
    <li class="radio input optional" id="plan_tier_input"><fieldset class="choices"><legend class="label"><label>Tier</label></legend><ol class="choices-group">
      <li class="choice"><label for="plan_tier_basic"><input id="plan_tier_basic" type="radio" name="plan[tier]" value="basic" checked>Basic</label></li>
      <li class="choice"><label for="plan_tier_plus"><input id="plan_tier_plus" type="radio" name="plan[tier]" value="plus">Plus</label></li>
    </ol></fieldset></li>
    <li class="check_boxes input optional" id="plan_channels_input"><fieldset class="choices"><legend class="label"><label>Channels</label></legend><ol class="choices-group">
      <li class="choice"><label for="plan_channels_sms"><input id="plan_channels_sms" type="checkbox" name="plan[channels][]" value="sms" checked>SMS</label></li>
      <li class="choice"><label for="plan_channels_email"><input id="plan_channels_email" type="checkbox" name="plan[channels][]" value="email">Email</label></li>
    </ol></fieldset></li>
    <li class="boolean input optional" id="plan_active_input"><input type="hidden" name="plan[active]" value="0"><label for="plan_active"><input id="plan_active" type="checkbox" name="plan[active]" value="1" checked>Active</label></li>
    <li class="text input optional" id="plan_notes_input"><label class="label" for="plan_notes">Notes</label><textarea id="plan_notes" name="plan[notes]" rows="3">Coordinate with the copy editor before week 2.</textarea></li>
    <li class="file input optional" id="plan_document_input"><label class="label" for="plan_document">Document</label><input id="plan_document" type="file" name="plan[document]"></li>
    <li class="string input optional stringish" id="plan_code_input"><label class="label" for="plan_code">Plan code</label><input id="plan_code" type="text" value="WC-12" disabled></li>
    <li class="string input required error stringish" id="plan_owner_input"><label class="label" for="plan_owner">Owner<abbr title="required">*</abbr></label><input id="plan_owner" name="plan[owner]" type="text"><p class="inline-errors">can't be blank</p></li>
  </ol></fieldset>
  <fieldset class="actions"><ol>
    <li class="action input_action" id="plan_submit_action"><input type="submit" name="commit" value="Save plan"></li>
    <li class="cancel"><a href="/admin/content_plans">Cancel</a></li>
  </ol></fieldset>
</form>`

const blocks = `
<div class="flash flash_notice">Plan saved.</div>
<div class="columns">
  <div class="column"><div class="panel"><h3>Plan</h3><div class="panel_contents"><div class="attributes_table"><table><tbody>
    <tr><th>Name</th><td>Weekly digest, 12 weeks</td></tr>
    <tr><th>Status</th><td><span class="status_tag yes">Active</span></td></tr>
    <tr><th>Tier</th><td><span class="status_tag warn">Plus</span> <span class="status_tag error">Overdue</span></td></tr>
  </tbody></table></div></div></div></div>
  <div class="column"><div class="panel"><h3>Revisions</h3><div class="panel_contents"><table class="index_table"><thead><tr><th>When</th><th>With</th></tr></thead><tbody>
    <tr><td>Oct 20</td><td>Sarah Chen</td></tr><tr><td>Oct 27</td><td>Lauren Thompson</td></tr>
  </tbody></table></div></div></div>
</div>
<p>See <a href="https://example.com/style-guide">the style guide</a> or <code>content_plan#run</code> for details. <a class="button" href="/admin/content_plans/1/edit">Edit plan</a></p>
<ul><li>Weekly check-in</li><li>Daily draft review</li></ul>
<div class="blank_slate_container"><span class="blank_slate">No documents yet.</span></div>`

const meta = {
  title: 'Frame/FrameView',
  component: FrameView,
  parameters: { viewportSize: { width: 900, height: 1500 } },
} satisfies Meta<typeof FrameView>

export default meta
type Story = StoryObj<typeof meta>

export const FormtasticControls: Story = { args: { html: kitchenSink, src: '/admin/content_plans/1/edit' } }

export const FormtasticControlsDark: Story = { ...FormtasticControls, globals: { theme: 'dark' } }

export const FormtasticMobile: Story = { ...FormtasticControls, parameters: { viewportSize: { width: 390, height: 1400 } } }

export const PanelsTablesAndTags: Story = { args: { html: blocks, src: '/admin/content_plans/1' }, parameters: { viewportSize: { width: 900, height: 720 } } }

export const PanelsTablesAndTagsDark: Story = { ...PanelsTablesAndTags, globals: { theme: 'dark' } }

export const Bare: Story = { args: { html: blocks, bare: true }, parameters: { viewportSize: { width: 900, height: 640 } } }

// Classic pages repeat their title as a heading; the page or dialog around the frame already shows it.
export const RepeatedTitleIsHidden: Story = {
  args: { title: 'Team history', html: '<h2>Team history</h2><p>Three members.</p><h3>Other heading</h3>', bare: true },
  parameters: { viewportSize: { width: 600, height: 200 } },
  play: async ({ canvasElement }) => {
    await expect(within(canvasElement).getByRole('heading', { name: 'Other heading' })).toBeVisible()
    await expect(within(canvasElement).queryByRole('heading', { name: 'Team history' })).toBeNull()
  },
}

// A bare `select_tag` has no label in classic either; the field's own name stands in for it.
export const UnlabeledSelectIsNamed: Story = {
  args: { html: '<form method="get"><select name="state" id="state"><option value=""></option><option value="NY">New York</option></select> <input type="submit" value="Filter"></form>' },
  parameters: { viewportSize: { width: 600, height: 120 } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('combobox', { name: 'State' })).toBeVisible()
  },
}

export const DangerousMarkupIsStripped: Story = {
  args: { html: '<p id="safe">Safe <a href="/admin/x" onclick="window.__pwned = true">link</a></p><script>window.__pwned = true</script><iframe src="/x"></iframe><style>body{display:none}</style>' },
  parameters: { viewportSize: { width: 600, height: 240 } },
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByText('Safe'))
    // next-themes injects its own nonce'd script into the canvas.
    await expect(canvasElement.querySelector('script:not([nonce]), iframe, style')).toBeNull()
    await expect(canvasElement.querySelector('[onclick]')).toBeNull()
  },
}
