import './index.css'

// Was <title> + <link rel="icon"> in the old index.html.
export const metadata = {
  title: 'Mojo Product Crawler',
  icons: { icon: '/favicon.svg' },
}

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
