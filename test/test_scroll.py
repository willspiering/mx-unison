import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import mxscroll

class Scroll(unittest.TestCase):
    def test_factors(self):
        self.assertEqual(mxscroll.factor(.25), .25)
        self.assertEqual(mxscroll.factor(4), 4)
        for raw in (True, 0, 5, float('nan'), float('inf'), 'bad'):
            with self.assertRaises((ValueError,TypeError)): mxscroll.factor(raw)

    def test_lua_rejects_injection(self):
        for name in ('mouse"}); os.execute("bad")', '<img src=x>', 'a\n'):
            with self.assertRaises(ValueError): mxscroll.lua(name, 2)
        self.assertIn('scroll_factor = 2.0', mxscroll.lua('mx-master-3s', 2))
        self.assertIn('input.scroll_factor', mxscroll.lua('mx-master-3s', None))

if __name__ == '__main__': unittest.main()
