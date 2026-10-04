/// Terms of use and the privacy policy, shown in the app. TERMS.md and PRIVACY.md at the repo root say the same
/// thing (test/legal_test.dart checks), so edit both together.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'ingredient.dart' show openLink;

sealed class LegalBlock {
  const LegalBlock();
}

/// A paragraph.
class P extends LegalBlock {
  final String text;
  const P(this.text);
}

/// A bullet point.
class Li extends LegalBlock {
  final String text;
  const Li(this.text);
}

/// Quoted text (the GPL's own words).
class Q extends LegalBlock {
  final String label;
  final String text;
  const Q(this.label, this.text);
}

/// A link that opens in the browser.
class L extends LegalBlock {
  final String label;
  final String url;
  const L(this.label, this.url);
}

class LegalSection {
  final String heading;
  final List<LegalBlock> blocks;
  const LegalSection(this.heading, this.blocks);
}

class LegalDoc {
  final String title;
  final String updated;
  final List<LegalBlock> intro;
  final List<LegalSection> sections;
  const LegalDoc(this.title, this.updated, this.intro, this.sections);
}

/// The GPL no-warranty line on the Learn screen.
const noWarranty = 'This app comes with no warranty, to the extent permitted by law; see the GNU GPL version 3, '
    'sections 15 and 16.';

const _updated = 'Last updated: October 3, 2026';

const termsDoc = LegalDoc('Terms of use and disclaimer', _updated, [
  P('These terms cover the I Hate Perfume app from ihateperfume.com. By using the app, you agree to them. If you '
      'don’t agree, please don’t use the app. These terms are also published at https://ihateperfume.com/app-terms/.'),
], [
  LegalSection('Information, not medical advice', [
    P('The app shows information about ingredients. It is not medical advice and not a diagnosis, and it doesn’t '
        'replace a doctor, an allergist, or a pharmacist.'),
    P('If you have allergies, asthma, skin reactions, or other health concerns, ask a qualified professional which '
        'products are right for you.'),
    P('In an emergency, call 911 or your local emergency number.'),
  ]),
  LegalSection('Never a guarantee', [
    P('The app never says a product is “safe,” and nothing in it guarantees that a product is free of fragrance or '
        'of any other ingredient.'),
    Li('Ingredient flags come from the sources named next to each flag. Those lists may be incomplete. An '
        'ingredient that isn’t on any list hasn’t been shown to be safe; it may never have been assessed.'),
    Li('Labels and formulas change, sometimes without a new barcode. Product data from Open Beauty Facts and Open '
        'Products Facts is added by volunteers and may be wrong, incomplete, or out of date. FDA drug labels come '
        'from the makers and may not match the package you have.'),
    Li('Text recognition can misread a label, and a typed list can have typos. Check what the app read against '
        'the package.'),
    P('Always read the actual package before you buy or use a product.'),
  ]),
  LegalSection('No warranty', [
    P('The app is free software under the GNU General Public License version 3 (GPL). It comes with no warranty, '
        'to the extent permitted by law. The information it shows is provided as is, and you use it at your own '
        'risk. Sections 15 and 16 of the GPL say:'),
    Q('15. Disclaimer of Warranty.',
        'THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE '
            'STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT '
            'WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED '
            'WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY '
            'AND PERFORMANCE OF THE PROGRAM IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF '
            'ALL NECESSARY SERVICING, REPAIR OR CORRECTION.'),
    Q('16. Limitation of Liability.',
        'IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY '
            'OTHER PARTY WHO MODIFIES AND/OR CONVEYS THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, '
            'INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY '
            'TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR '
            'LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER '
            'PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.'),
    P('Some places don’t allow these limits. Where that’s the case, they apply as far as the law allows.'),
    L('GNU General Public License version 3', 'https://www.gnu.org/licenses/gpl-3.0.html'),
  ]),
  LegalSection('Brand and product names', [
    P('Product names, brand names, and trademarks shown in the app belong to their owners. Showing them doesn’t '
        'mean those companies are connected to ihateperfume.com or endorse the app, or that we endorse them.'),
  ]),
  LegalSection('Data and links', [
    P('Product names and ingredient lists come from Open Beauty Facts and Open Products Facts, under the Open '
        'Database License (ODbL), and for over-the-counter drugs such as sunscreen and antiperspirant, from FDA drug '
        'labels through the U.S. Food and Drug Administration’s openFDA service, which are in the public domain. '
        'Ingredient flags come from the ihateperfume.com label decoder, which names the official source of each '
        'flag.'),
    P('Links to other websites, such as ihateperfume.com, EWG, official sources, and a maker’s ingredient page, '
        'open in your browser only when you tap them. Those sites have their own terms and privacy policies.'),
    L('Open Beauty Facts', 'https://world.openbeautyfacts.org'),
    L('Open Products Facts', 'https://world.openproductsfacts.org'),
    L('Open Database License (ODbL)', 'https://opendatacommons.org/licenses/odbl/1-0/'),
    L('openFDA', 'https://open.fda.gov'),
    L('openFDA terms of service', 'https://open.fda.gov/terms/'),
    L('Label decoder on ihateperfume.com', 'https://ihateperfume.com/label-decoder/'),
  ]),
  LegalSection('The app’s license', [
    P('The app’s source code is under the GPL with additional terms: keep the credit to ihateperfume.com, mark '
        'modified versions as different, and don’t use the I Hate Perfume name or logos for them. These terms of '
        'use don’t take away any right the GPL gives you.'),
  ]),
  LegalSection('Changes', [
    P('We may update these terms. The date at the top shows when they last changed, and the current version is '
        'always in the app. If you keep using the app after a change, the new terms apply.'),
  ]),
  LegalSection('Contact', [
    P('Questions? Email admin@ihateperfume.com or use the contact page on ihateperfume.com.'),
    L('Contact ihateperfume.com', 'https://ihateperfume.com/contact/'),
  ]),
]);

const privacyDoc = LegalDoc('Privacy policy', _updated, [
  P('I Hate Perfume is a free app from ihateperfume.com. It has no account, no ads, no analytics, and no '
      'tracking. This policy explains what the app does with your information. It is also published at '
      'https://ihateperfume.com/app-privacy/.'),
], [
  LegalSection('The short version', [
    Li('We don’t collect any personal information. There is no account, and nothing about you is sent.'),
    Li('Your scans stay on this phone. Only a barcode number is sent to look the product up, unless you choose to '
        'send us a product.'),
  ]),
  LegalSection('What leaves your phone', [
    Li('Barcode numbers. When you scan or type a barcode, the app sends that number to Open Beauty Facts '
        '(world.openbeautyfacts.org); if it finds no ingredient list there, to Open Products Facts '
        '(world.openproductsfacts.org); and if it still finds none, to the U.S. Food and Drug Administration’s '
        'openFDA service (api.fda.gov), which has the labels of over-the-counter drugs such as sunscreen; and if it '
        'still finds none, to ihateperfume.com, which has products we’ve checked ourselves. Only the barcode number '
        'is sent. Every copy of the app identifies itself the same way, and the request carries no '
        'account, device ID, or location. Like any website, these services see your IP address and may keep logs. Their '
        'privacy policies explain what they keep.'),
    Li('Ingredient data updates. About once a day, the app asks ihateperfume.com whether there is newer ingredient '
        'data, and downloads it if there is. The request carries nothing about you: no account, device ID, or '
        'location.'),
    Li('Fragrance-free finds. When you open the Finds tab, or pull to refresh it, the app downloads the list from '
        'ihateperfume.com. Nothing about you is sent.'),
    Li('Products you send us. Only if you choose to send us a product. You see exactly what will be sent before you '
        'tap Send: your photos of the package and the ingredient list, the barcode, and anything you typed or ticked. '
        'Location and all other photo details are removed on your phone before anything is sent, and your original '
        'photos aren’t changed. We keep the photos privately, never publish them, and delete them once we’ve reviewed '
        'them. If we approve the product, its name, ingredient list, and what the package says are published in the '
        'app and on ihateperfume.com. To stop abuse, our server limits how many products can be sent each day. It '
        'does this with a scrambled code made from your IP address that changes every day and is deleted after 48 '
        'hours. We never store your IP address.'),
    Li('Maker links. After a barcode scan, the app shows a link to the maker’s own ingredient page (for P&G '
        'products) or to SmartLabel’s product search (smartlabel.org, run by the Consumer Brands Association). '
        'Opening it sends the barcode to that website, and only when you tap the link. The app never contacts '
        'them on its own.'),
    Li('Links. Links to ihateperfume.com, EWG, and official sources open in your browser only when you tap them. '
        'From then on, that website’s privacy policy applies.'),
    Li('Sharing. If you tap Share on a result, Android’s share sheet opens and you choose where the text goes. '
        'Nothing is shared unless you choose it.'),
    P('Nothing else is sent: not the ingredient lists you read or type, not your recent scans, not your list, and '
        'no photos unless you choose to send us a product.'),
    L('Open Beauty Facts privacy policy', 'https://world.openbeautyfacts.org/privacy'),
    L('Open Products Facts privacy policy', 'https://world.openproductsfacts.org/privacy'),
    L('openFDA terms of service', 'https://open.fda.gov/terms/'),
    L('FDA website policies, including privacy', 'https://www.fda.gov/about-fda/about-website/website-policies'),
  ]),
  LegalSection('Camera and photos', [
    P('The app asks for one permission: the camera, to read barcodes and ingredient lists. You can turn it off in '
        'Android settings at any time and still type a barcode or an ingredient list.'),
    P('Barcodes and text are read on the phone by Google ML Kit, using models built into the app. We removed the '
        'part of ML Kit that would send usage statistics to Google, so those reports are dropped on the phone.'),
    P('Photos the app takes are deleted as soon as the text is read. If you pick a photo from your gallery '
        'instead, the original isn’t changed or uploaded; Android gives the app a temporary copy, which is also '
        'deleted as soon as the text is read.'),
    L('Google ML Kit terms', 'https://developers.google.com/ml-kit/terms'),
  ]),
  LegalSection('What’s stored on your phone', [
    P('These are stored only on this phone, in the app’s private storage:'),
    Li('your recent scans (product name, barcode, ingredient list, and date)'),
    Li('the product type you chose'),
    Li('your personal ingredient list, if you make one'),
    Li('a note that you’ve seen the first-run notice'),
    P('They’re left out of Android backups and device-to-device transfers, so they don’t go to Google’s cloud or '
        'to a new phone.'),
    P('To delete them, tap Clear next to Recent scans on the Scan screen, clear the app’s storage in Android '
        'settings, or uninstall the app.'),
  ]),
  LegalSection('What we don’t do', [
    P('No analytics, no ads, no crash reporting, no accounts, and no tracking. We don’t sell or share data about '
        'you, because we don’t have any.'),
  ]),
  LegalSection('Android and Google Play', [
    P('Android and Google Play are run by Google and follow your own settings and Google’s privacy policy. For '
        'example, Google Play records app installs, and Android may send crash and usage reports to Google if you '
        'turned that on. Google gives app developers summaries of some of this, such as install counts and crash '
        'reports, without names or contact details. We don’t control what Google collects.'),
    L('Google privacy policy', 'https://policies.google.com/privacy'),
  ]),
  LegalSection('Children', [
    P('The app isn’t directed at children under 13, and it collects no personal information from anyone, '
        'including children.'),
  ]),
  LegalSection('Your choices and rights', [
    P('Because we hold no personal information about you, there’s nothing for us to show you, correct, or '
        'delete. What’s on your phone is under your control (see above). For data held by Open Beauty Facts, Open '
        'Products Facts, the FDA, or Google, contact them.'),
  ]),
  LegalSection('Changes', [
    P('If the app changes what it sends or stores (for example, downloading updated ingredient data from '
        'ihateperfume.com, or letting you submit a missing product), we’ll update this policy first. The date at '
        'the top shows when it last changed.'),
  ]),
  LegalSection('Contact', [
    P('Questions? Email admin@ihateperfume.com or use the contact page on ihateperfume.com.'),
    L('Contact ihateperfume.com', 'https://ihateperfume.com/contact/'),
  ]),
]);

/// One legal document, in the app's style.
class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  final String back;
  const LegalScreen(this.doc, {super.key, this.back = 'Learn'});

  static Route<void> route(LegalDoc doc, {String back = 'Learn'}) =>
      MaterialPageRoute(builder: (_) => LegalScreen(doc, back: back));

  Widget _block(BuildContext context, LegalBlock b) => switch (b) {
        P(:final text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: T.lede)),
        Li(:final text) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 7, right: 10),
                  child: SizedBox(width: 8, height: 8, child: ColoredBox(color: C.signal))),
              Expanded(child: Text(text, style: T.lede)),
            ]),
          ),
        Q(:final label, :final text) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Mono(label, size: 11),
                const SizedBox(height: 6),
                Text(text, style: T.src()),
              ]),
            ),
          ),
        L(:final label, :final url) => Rule(
            onTap: () => openLink(context, url),
            child: Row(children: [
              Expanded(child: Text(label, style: T.lede.copyWith(fontWeight: FontWeight.w600))),
              const Icon(Icons.north_east, size: 18, color: C.signal),
            ]),
          ),
      };

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              TopBar(left: TopBar.back(context, back)),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
                  Big(doc.title, size: 40),
                  const SizedBox(height: 8),
                  Mono(doc.updated, size: 11, color: C.muted),
                  const SizedBox(height: 14),
                  for (final b in doc.intro) _block(context, b),
                  for (final s in doc.sections) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(0, 18, 0, 8), child: Mono(s.heading, color: C.signal)),
                    for (final b in s.blocks) _block(context, b),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Markdown for a legal document, as in TERMS.md and PRIVACY.md (without their draft line).
String legalMarkdown(LegalDoc doc) {
  final out = StringBuffer('# ${doc.title}\n\n${doc.updated}\n');
  void blocks(List<LegalBlock> bs) {
    LegalBlock? prev;
    for (final b in bs) {
      final list = (b is Li || b is L) && (prev is Li || prev is L);
      if (!list) out.write('\n');
      out.write(switch (b) {
        P(:final text) => text,
        Li(:final text) => '- $text',
        Q(:final label, :final text) => '> **$label** $text',
        L(:final label, :final url) => '- [$label]($url)',
      });
      out.write('\n');
      prev = b;
    }
  }

  blocks(doc.intro);
  for (final s in doc.sections) {
    out.write('\n## ${s.heading}\n');
    blocks(s.blocks);
  }
  return out.toString();
}
