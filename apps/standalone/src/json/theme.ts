import type { Theme } from 'json-edit-react'

// Colors come from the app's CSS variables, so light and dark follow the theme class without a re-render.
// Value types read by hue and by style (string/number/boolean/null differ in more than color alone).
export const jsonTheme: Theme = {
  displayName: 'reactiveadmin',
  styles: {
    container: { backgroundColor: 'transparent', color: 'var(--foreground)', fontFamily: 'var(--font-mono)', fontSize: 'var(--text-xs)' },
    property: 'var(--foreground)',
    bracket: { color: 'var(--muted-foreground)', fontWeight: 'normal' },
    itemCount: { color: 'var(--muted-foreground)', fontStyle: 'normal' },
    string: 'var(--success)',
    number: 'var(--info)',
    boolean: { color: 'var(--warning)', fontWeight: 600 },
    null: { color: 'var(--muted-foreground)', fontStyle: 'italic' },
    input: { backgroundColor: 'var(--background)', color: 'var(--foreground)', border: '1px solid var(--input)', borderRadius: 'var(--radius-sm)' },
    inputHighlight: 'color-mix(in srgb, var(--warning) 32%, transparent)',
    error: { color: 'var(--danger)', fontWeight: 600 },
    iconCollection: 'var(--muted-foreground)',
    iconCopy: 'var(--muted-foreground)',
    iconEdit: 'var(--muted-foreground)',
    iconDelete: 'var(--danger)',
    iconAdd: 'var(--success)',
    iconOk: 'var(--success)',
    iconCancel: 'var(--danger)',
  },
}
