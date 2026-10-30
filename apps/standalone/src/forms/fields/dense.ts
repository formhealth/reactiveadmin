import { createContext, useContext } from 'react'

// Set around the control of a compact list row: the section heading labels the list, so the control keeps its
// label for assistive tech only and drops its hint.
export const DenseContext = createContext<{ label: string } | undefined>(undefined)

export const useDense = () => useContext(DenseContext)
