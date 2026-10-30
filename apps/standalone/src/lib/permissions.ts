import type { Row } from '@/api/generated/model'

// With `defaults` off (AA `actions defaults: false`) only the row's own actions count, not View and Edit.
export const hasRowActions = ({ permissions, actions }: Row, defaults = true) => !!((defaults && (permissions.show || permissions.update)) || actions?.length)
