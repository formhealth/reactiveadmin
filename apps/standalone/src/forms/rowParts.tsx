import { useRecordFormContext } from './formContext'
import type { FieldProps } from './context'

export function FormFieldView({ field, name }: FieldProps) {
  const { registry } = useRecordFormContext()
  const Control = registry[field.control] ?? registry.text
  return <Control field={field} name={name} />
}

// What the server said about a row as a whole, or about an attribute the row has no control for.
export const RowNotes = ({ notes }: { notes?: string[] }) =>
  notes?.length ? (
    <ul role="alert" className="flex flex-col gap-0.5 text-xs font-medium text-danger">
      {notes.map((note) => (
        <li key={note}>{note}</li>
      ))}
    </ul>
  ) : null
