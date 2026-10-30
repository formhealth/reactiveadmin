import type { FieldRegistry } from './context'
import { BooleanField, CheckboxesField, RadioField, SelectField } from './fields/ChoiceFields'
import { Combobox } from './fields/Combobox'
import { DateField, DateTimeField, TimeField } from './fields/DateFields'
import { ContentField, FileField, HiddenField, HtmlField } from './fields/RichFields'
import { TextField } from './fields/TextField'
import { JsonField } from '@/json/JsonField'

export const defaultRegistry: FieldRegistry = {
  text: TextField,
  textarea: TextField,
  number: TextField,
  email: TextField,
  url: TextField,
  phone: TextField,
  password: TextField,
  select: SelectField,
  multiselect: Combobox,
  typeahead: Combobox,
  boolean: BooleanField,
  radio: RadioField,
  checkboxes: CheckboxesField,
  date: DateField,
  datetime: DateTimeField,
  time: TimeField,
  json: JsonField,
  file: FileField,
  hidden: HiddenField,
  html: HtmlField,
  content: ContentField,
}
