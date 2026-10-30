import { createContext, useContext } from 'react'
import { sharedOptionLookup, type OptionLookup } from './optionLookup'

export const OptionLookupContext = createContext<OptionLookup | undefined>(undefined)

export const useOptionLookup = () => useContext(OptionLookupContext) ?? sharedOptionLookup
