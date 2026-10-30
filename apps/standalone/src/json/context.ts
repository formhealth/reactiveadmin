import { createContext, useContext } from 'react'

// The attribute row's label ("Audited changes"), so a json node can tell what it is showing.
export const FieldLabelContext = createContext<string>('')
export const useFieldLabel = () => useContext(FieldLabelContext)
