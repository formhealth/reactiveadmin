import { useState } from 'react'
import { FormProvider } from 'react-hook-form'
import { createOptionLookup } from './fields/optionLookup'
import { OptionLookupContext } from './fields/optionLookupContext'
import { FormContext, type FormContextValue } from './formContext'

export type { FieldProps, FieldRegistry } from './formContext'

export function RecordFormProvider({ form, registry, plain, children }: FormContextValue & { children: React.ReactNode }) {
  // Selected-value labels are looked up once per form: batched across its typeaheads and kept while it is open.
  const [optionLookup] = useState(() => createOptionLookup())
  return (
    <FormContext value={{ form, registry, plain }}>
      <OptionLookupContext value={optionLookup}>
        <FormProvider {...form.methods}>{children}</FormProvider>
      </OptionLookupContext>
    </FormContext>
  )
}
