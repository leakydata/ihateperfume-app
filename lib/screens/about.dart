import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import 'ingredient.dart';
import 'legal.dart';

/// "Learn": what the app promises, where the data comes from, and the required attribution.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget h(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 22, 0, 8), child: Mono(t, color: C.signal));
    Widget p(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: T.lede));
    Widget link(String t, String url) => Rule(
          onTap: () => openLink(context, url),
          child: Row(children: [
            Expanded(child: Text(t, style: T.lede.copyWith(fontWeight: FontWeight.w600))),
            const Icon(Icons.north_east, size: 18, color: C.signal),
          ]),
        );
    Widget page(String t, LegalDoc doc) => Rule(
          onTap: () => Navigator.of(context).push(LegalScreen.route(doc)),
          child: Row(children: [
            Expanded(child: Text(t, style: T.lede.copyWith(fontWeight: FontWeight.w600))),
            const Icon(Icons.arrow_forward, size: 18, color: C.signal),
          ]),
        );
    return Column(children: [
      TopBar(left: Text('LEARN', style: T.big(30).copyWith(height: 1))),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
          const Big('Scan it.', size: 44),
          const Big('Unmask it.', size: 44, color: C.signal),
          const SizedBox(height: 12),
          p('Scan a barcode or photograph an ingredient list to see the scent ingredients, fragrance allergens, '
              'and other flags in it. Every flag names its source.'),
          h('Our promises'),
          for (final t in const [
            'No account, no ads, no tracking. Free.',
            'Barcode reading, text recognition, and ingredient matching run on this phone.',
            'Your photos never leave the phone. They’re deleted as soon as the text is read.',
            'Only a scanned barcode number is sent, to Open Beauty Facts, then Open Products Facts, then the FDA’s '
                'openFDA service, to find the product. Nothing else goes anywhere.',
            'Recent scans are stored only on this phone and left out of phone backups.',
            'We never say a product is “safe.” Not on a list doesn’t mean safe; it may never have been assessed.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 7, right: 10), child: SizedBox(width: 8, height: 8, child: ColoredBox(color: C.signal))),
                Expanded(child: Text(t, style: T.lede)),
              ]),
            ),
          h('What this can’t check'),
          for (final t in decoder.limits) p(t),
          p('No fragrance on our lists is a good sign, but not a guarantee. ${decoder.caution}'),
          h('Where the data comes from'),
          p('Ingredient flags come from the ihateperfume.com label decoder: official lists (EU Cosmetics Regulation '
              'annexes, EU CLP, IARC, the EU endocrine disruptor lists, IFRA, and FDA’s PFAS report), the Campaign '
              'for Safe Cosmetics, and graded research. Data version $dataVersion.'),
          p('Product ingredient lists come from Open Beauty Facts and Open Products Facts, made by volunteers and '
              'available under the Open Database License (ODbL). Thank you to everyone who adds products there. '
              'For over-the-counter drugs such as sunscreen and antiperspirant, they also come from FDA drug labels '
              'through openFDA (public domain).'),
          link('Label decoder on ihateperfume.com', 'https://ihateperfume.com/label-decoder/'),
          link('Open Beauty Facts', 'https://world.openbeautyfacts.org'),
          link('Open Products Facts', 'https://world.openproductsfacts.org'),
          link('Open Database License (ODbL)', 'https://opendatacommons.org/licenses/odbl/1-0/'),
          link('openFDA', 'https://open.fda.gov'),
          h('Terms and privacy'),
          p('Information, not medical advice. Never a guarantee: always read the package.'),
          page('Terms and disclaimer', termsDoc),
          page('Privacy policy', privacyDoc),
          h('License'),
          p('Based on the I Hate Perfume app by ihateperfume.com (https://ihateperfume.com).'),
          Text(
            'Free software under the GNU General Public License version 3, with additional terms: keep this credit, '
            'mark modified versions as different, and don’t use the I Hate Perfume name or logos for them. '
            'Fonts: Archivo and IBM Plex Mono, SIL Open Font License.',
            style: T.src(),
          ),
          const SizedBox(height: 8),
          Text(noWarranty, style: T.src()),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => showLicensePage(
                context: context,
                applicationName: 'I Hate Perfume',
                applicationLegalese: 'Based on the I Hate Perfume app by ihateperfume.com (https://ihateperfume.com).'),
            child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: MonoLink('Open-source licenses', icon: Icons.arrow_forward, color: C.ink)),
          ),
        ]),
      ),
    ]);
  }
}
