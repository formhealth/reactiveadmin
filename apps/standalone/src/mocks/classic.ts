import { http, HttpResponse, delay } from 'msw'
import type { FrameRedirect } from '@/api/generated/model'
import { authorIndex } from './authors'
import { uuid } from './fixtures'

// Classic-admin fragments as the gem serves them to a frame request (layout-less HTML): Formtastic forms, index tables,
// and a raw `form_with`. Writes come back as a re-rendered fragment (422) or a FrameRedirect.

const html = (body: string, status = 200) => new HttpResponse(body, { status, headers: { 'Content-Type': 'text/html; charset=utf-8' } })

const redirect = (body: FrameRedirect) => HttpResponse.json(body)

const members = [
  { id: 1, name: 'Sarah Chen', role: 'Editor', active: true, started: 'Sep 3, 2026', ended: '' },
  { id: 2, name: 'Lauren Thompson', role: 'Copy editor', active: true, started: 'Sep 3, 2026', ended: '' },
  { id: 3, name: 'Marcus Johnson', role: 'Proofreader', active: false, started: 'Jun 12, 2026', ended: 'Sep 2, 2026' },
]

const memberId = (author: string, member: number) => `p${authorIndex(author)}m${member}`

export const teamHistory = (author: string) => `
<div class="panel">
  <h3>Members</h3>
  <div class="panel_contents">
    <table class="index_table index">
      <thead><tr><th class="col col-member">Member</th><th class="col">Role</th><th class="col">Status</th><th class="col">Started</th><th class="col">Ended</th><th class="col"></th></tr></thead>
      <tbody>
        ${members
          .map(
            (m) => `<tr id="team_member_${m.id}">
          <td class="col col-member"><a href="/admin/team_members/${memberId(author, m.id)}">${m.name}</a></td>
          <td class="col">${m.role}</td>
          <td class="col"><span class="status_tag ${m.active ? 'active ok' : ''}">${m.active ? 'Active' : 'Ended'}</span></td>
          <td class="col">${m.started}</td>
          <td class="col">${m.ended || '<span class="empty">Empty</span>'}</td>
          <td class="col col-actions"><div class="table_actions">
            <a class="member_link" href="/admin/team_members/${memberId(author, m.id)}">View</a>
            ${m.active ? `<a class="member_link delete_link" data-confirm="Remove ${m.name} from this team?" rel="nofollow" data-method="delete" href="/admin/team_members/${memberId(author, m.id)}">Remove</a>` : ''}
          </div></td>
        </tr>`,
          )
          .join('')}
      </tbody>
    </table>
    <p style="margin-top: 1rem">
      <a class="button" href="/admin/authors/${author}/team_members/new" onclick="alert('this handler is stripped')">Add team member</a>
      <a style="margin-left: 0.75rem" href="/admin/authors/${author}/team_history.csv">Download CSV</a>
      <a style="margin-left: 0.75rem" href="/admin/authors/${author}">Back to author</a>
    </p>
  </div>
  <script>alert('scripts are stripped')</script>
</div>`

type Draft = { name?: string; role?: string; started?: string; errors?: Record<string, string> }

const field = (name: keyof Draft, label: string, control: string, errors: Draft['errors'] = {}) =>
  `<div class="field${errors[name] ? ' error' : ''}"><label for="team_member_${name}">${label}</label>${control}${errors[name] ? `<p class="inline-errors">${errors[name]}</p>` : ''}</div>`

export const newMemberForm = (author: string, { name = '', role = '', started = '', errors }: Draft = {}) => `
${
  errors
    ? `<div id="error_explanation" class="flash flash_alert"><strong>${Object.keys(errors).length} errors prohibited this member from being saved</strong></div>`
    : ''
}
<form action="/admin/authors/${author}/team_members" accept-charset="UTF-8" method="post">
  <input type="hidden" name="authenticity_token" value="rails-form-token" autocomplete="off">
  ${field('name', 'Name', `<input type="text" name="team_member[name]" id="team_member_name" value="${name}">`, errors)}
  ${field(
    'role',
    'Role',
    `<select name="team_member[role]" id="team_member_role"><option value="">Select a role</option>${[['editor', 'Editor'], ['copy_editor', 'Copy editor'], ['photographer', 'Photographer']]
      .map(([value, text]) => `<option value="${value}"${role === value ? ' selected' : ''}>${text}</option>`)
      .join('')}</select>`,
    errors,
  )}
  ${field('started', 'Start date', `<input type="date" name="team_member[started_on]" id="team_member_started" value="${started}">`, errors)}
  <div class="actions"><input type="submit" name="commit" value="Add member" data-disable-with="Add member"></div>
</form>`

export const memberDetail = (id: string) => `
<div class="panel">
  <h3>Team member</h3>
  <div class="panel_contents">
    <div class="attributes_table"><table><tbody>
      <tr><th>Name</th><td>Sarah Chen</td></tr>
      <tr><th>Role</th><td>Editor</td></tr>
      <tr><th>Status</th><td><span class="status_tag active ok">Active</span></td></tr>
    </tbody></table></div>
    <p style="margin-top: 1rem"><a href="/admin/authors/${uuid(Number(/^p(\d+)/.exec(id)?.[1] ?? 0))}/team_history">Back to team history</a></p>
  </div>
</div>`

const KINDS = [['lift_embargoes', 'Lift expired embargoes'], ['republish_failed', 'Republish failed posts'], ['backfill_publisher', 'Backfill publisher ids']]

export const batchForm = ({ kind = '', name = '', runOn = '', error = '' } = {}) => `
<form class="formtastic batch_operation" id="new_batch_operation" action="/admin/batch_operations/run" accept-charset="UTF-8" method="post">
  <input type="hidden" name="authenticity_token" value="rails-form-token" autocomplete="off">
  <fieldset class="inputs"><legend><span>Batch details</span></legend><ol>
    <li class="select input required${error ? ' error' : ''}" id="batch_operation_kind_input">
      <label for="batch_operation_kind" class="label">Operation<abbr title="required">*</abbr></label>
      <select id="batch_operation_kind" name="batch_operation[kind]"><option value="">Please select</option>${KINDS.map(([value, text]) => `<option value="${value}"${kind === value ? ' selected' : ''}>${text}</option>`).join('')}</select>
      ${error ? `<p class="inline-errors">${error}</p>` : ''}
    </li>
    <li class="string input optional stringish" id="batch_operation_name_input">
      <label for="batch_operation_name" class="label">Label</label>
      <input id="batch_operation_name" type="text" name="batch_operation[name]" value="${name}">
      <p class="inline-hints">Shown in the batch history.</p>
    </li>
    <li class="date_picker input optional" id="batch_operation_run_on_input">
      <label for="batch_operation_run_on" class="label">Run on</label>
      <input id="batch_operation_run_on" class="datepicker" data-reactiveadmin-widget="date" type="text" name="batch_operation[run_on]" value="${runOn}" placeholder="yyyy-mm-dd" maxlength="10" size="10">
    </li>
    <li class="boolean input optional" id="batch_operation_dry_run_input">
      <input type="hidden" name="batch_operation[dry_run]" value="0"><label for="batch_operation_dry_run"><input type="checkbox" id="batch_operation_dry_run" name="batch_operation[dry_run]" value="1" checked="checked">Dry run (report only, no changes)</label>
    </li>
  </ol></fieldset>
  <fieldset class="actions"><ol>
    <li class="action input_action" id="batch_operation_submit_action"><input type="submit" name="commit" value="Start batch" data-disable-with="Start batch"></li>
    <li class="cancel"><a href="/admin/batch_operations">Cancel</a></li>
  </ol></fieldset>
</form>`

const formParams = async (request: Request) => Object.fromEntries((await request.formData()) as unknown as Iterable<[string, string]>)

export const classicHandlers = [
  http.get('/admin/authors/:id/team_history', async ({ params }) => {
    await delay(150)
    return html(teamHistory(String(params.id)))
  }),

  http.get('/admin/authors/:id/team_history.csv', () =>
    new HttpResponse('member,role,status\nSarah Chen,Editor,Active\n', { headers: { 'Content-Type': 'text/csv', 'Content-Disposition': 'attachment; filename="team-history.csv"' } }),
  ),

  http.get('/admin/authors/:id/team_members/new', async ({ params }) => {
    await delay(100)
    return html(newMemberForm(String(params.id)))
  }),

  http.post('/admin/authors/:id/team_members', async ({ params, request }) => {
    await delay(250)
    const id = String(params.id)
    const body = await formParams(request)
    const errors = {
      ...(body['team_member[name]'] ? {} : { name: "can't be blank" }),
      ...(body['team_member[role]'] ? {} : { role: "can't be blank" }),
    }
    if (Object.keys(errors).length)
      return html(newMemberForm(id, { name: body['team_member[name]'], role: body['team_member[role]'], started: body['team_member[started_on]'], errors }), 422)
    return redirect({
      redirect: { url: `/admin/authors/${id}`, resource: 'authors', id, view: 'show' },
      flash: { notice: `${body['team_member[name]']} was added to the team` },
    })
  }),

  http.get('/admin/team_members/:id', async ({ params }) => html(memberDetail(String(params.id)))),

  http.post('/admin/team_members/:id', async ({ params, request }) => {
    await delay(200)
    const body = await formParams(request)
    const author = uuid(Number(/^p(\d+)/.exec(String(params.id))?.[1] ?? 0))
    return body._method === 'delete'
      ? redirect({ redirect: { url: `/admin/authors/${author}/team_history` }, flash: { notice: 'Team member was removed' } })
      : html('', 405)
  }),

  http.get('/admin/batch_operations', () => html(batchForm())),

  http.post('/admin/batch_operations/run', async ({ request }) => {
    await delay(250)
    const body = await formParams(request)
    const kind = body['batch_operation[kind]']
    if (!kind) return html(batchForm({ name: body['batch_operation[name]'], runOn: body['batch_operation[run_on]'], error: "can't be blank" }), 422)
    return redirect({ redirect: { url: '/admin/batch_operations' }, flash: { notice: `Batch "${KINDS.find(([value]) => value === kind)?.[1]}" started` } })
  }),
]
