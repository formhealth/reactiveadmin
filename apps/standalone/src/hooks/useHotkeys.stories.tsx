import type { Meta, StoryObj } from '@storybook/react-vite'
import { useState } from 'react'
import { expect, userEvent, within } from 'storybook/test'
import { useHotkeys } from './useHotkeys'

// Counts the page-level "next row" shortcut beside widgets that own their keys.
function Harness() {
  const [moves, setMoves] = useState(0)
  useHotkeys({ down: () => setMoves((n) => n + 1), open: () => setMoves((n) => n + 100) })
  return (
    <div>
      <output aria-label="Moves">{moves}</output>
      <details>
        <summary>Details</summary>
        <p>Hidden content</p>
      </details>
      <div role="tree" aria-label="Tree" tabIndex={0} onKeyDown={(e) => e.key === 'ArrowDown' && e.preventDefault()}>
        <div role="treeitem" aria-selected="false">
          Item
        </div>
      </div>
      <button type="button">Elsewhere</button>
    </div>
  )
}

const meta = { title: 'Hooks/useHotkeys', component: Harness } satisfies Meta<typeof Harness>

export default meta
type Story = StoryObj<typeof meta>

export const EmbeddedWidgetsKeepTheirKeys: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    const moves = canvas.getByLabelText('Moves')

    canvas.getByText('Details').focus()
    await userEvent.keyboard('j{Enter}')
    await expect(moves).toHaveTextContent(/^0$/)

    canvas.getByRole('tree').focus()
    await userEvent.keyboard('{ArrowDown}')
    await expect(moves).toHaveTextContent(/^0$/)

    canvas.getByRole('button', { name: 'Elsewhere' }).focus()
    await userEvent.keyboard('j')
    await expect(moves).toHaveTextContent(/^1$/)
  },
}
