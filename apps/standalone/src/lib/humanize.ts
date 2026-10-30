export const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

export const humanize = (key: string) => capitalize(key.replace(/[._]+/g, ' ').trim())

// The manifest names a resource's plural label, but not until it has loaded: a raw key (`admin_policies`) must never show meanwhile.
export const pluralLabel = (summary: { plural_label?: string | null } | undefined, key: string) => summary?.plural_label ?? humanize(key)
